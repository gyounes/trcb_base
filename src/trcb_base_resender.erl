%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Georges Younes.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(trcb_base_resender).
-author("Georges Younes <georges.r.younes@gmail.com>").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% other
-export([add_exactly_once_queue/2]).

-include("trcb_base.hrl").

-record(state, {actor :: node(),
                metrics :: atom(),
                to_be_ack_queue :: dict:dict()}).

-type state_t() :: #state{}.

%%%===================================================================
%%% callbacks
%%%===================================================================

%% Add a message to a queue for at least once guarantee.
-spec add_exactly_once_queue(term(), term()) -> ok.
add_exactly_once_queue(Dot, Msg) ->
    gen_server:cast(?MODULE, {add_exactly_once_queue, Dot, Msg}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Same as start_link([]).
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% gen_server callbacks
%%%===================================================================

%% @private
-spec init(list()) -> {ok, state_t()}.
init([]) ->
    Actor = trcb_base_util:get_node(),

    %% Generate local to be acknowledged messages queue.
    ToBeAckQueue = dict:new(),

    schedule_resend(),

    {ok, #state{actor=Actor,
                metrics=trcb_base_config:get(lmetrics),
                to_be_ack_queue=ToBeAckQueue}}.

%% @private
-spec handle_call(term(), {pid(), term()}, state_t()) ->
    {reply, term(), state_t()}.
handle_call(Msg, _From, State) ->
    lager:warning("Unhandled cast messages: ~p", [Msg]),
    {reply, ok, State}.

%% @private
-spec handle_cast(term(), state_t()) -> {noreply, state_t()}.
handle_cast({add_exactly_once_queue, Dot, {VV, MessageBody, ToMembers}},
            #state{to_be_ack_queue=ToBeAckQueue0}=State) ->

    %% Get current time in milliseconds.
    CurrentTime = trcb_base_util:get_timestamp(),

    %% Add members to the queue of not ack messages and increment the vector clock.
    ToBeAckQueue = dict:store(Dot, {VV, MessageBody, ToMembers, CurrentTime}, ToBeAckQueue0),

    {noreply, State#state{to_be_ack_queue=ToBeAckQueue}};

handle_cast({tcbcast_ack, Dot, Sender},
    #state{to_be_ack_queue=ToBeAckQueue0}=State) ->

    ToBeAckQueue = case dict:find(Dot, ToBeAckQueue0) of
        %% Get list of waiting ackwnoledgements.
        {ok, {_VV, _MessageBody, Members0, _Timestamp}} ->
            %% Remove this member as an outstanding member.
            Members = lists:delete(Sender, Members0),

            case length(Members) of
                0 ->
                    %% None left, remove from ack queue.
                    dict:erase(Dot, ToBeAckQueue0);
                _ ->
                    %% Still some left, preserve.
                    dict:update(Dot, fun({A, B, _C, D}) -> {A, B, Members, D} end, ToBeAckQueue0)
            end;
        error ->
            ToBeAckQueue0
    end,

    {noreply, State#state{to_be_ack_queue=ToBeAckQueue}};

handle_cast(Msg, State) ->
    lager:warning("Unhandled cast messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec handle_info(term(), state_t()) -> {noreply, state_t()}.
handle_info(check_resend, #state{actor=Actor, to_be_ack_queue=ToBeAckQueue0, metrics=Metrics} = State) ->
    Now = trcb_base_util:get_timestamp(),
    ToBeAckQueue1 = dict:fold(
        fun(MessageDot, {MessageVV, MessageBody, MembersList, Timestamp0}, ToBeAckQueue) ->
            case (Now - Timestamp0) > ?WAIT_TIME_BEFORE_RESEND of
                true ->
                    Message1 = {tcbcast, MessageVV, MessageBody, Actor},
                    TaggedMessage1 = {?RESEND_TCBCAST_TAG, Message1},
                    %% Retransmit to membership.
                    trcb_base_util:send(TaggedMessage1, MembersList, Metrics, ?TCSB),

                    dict:update(MessageDot,
                                     fun({A, B, C, _D}) -> {A, B, C, trcb_base_util:get_timestamp()} end,
                                     ToBeAckQueue);
                false ->
                    %% Do nothing.
                    ToBeAckQueue
            end
        end,
        ToBeAckQueue0,
        ToBeAckQueue0
    ),

    schedule_resend(),

    {noreply, State#state{to_be_ack_queue=ToBeAckQueue1}};

handle_info(Msg, State) ->
    lager:warning("Unhandled info messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec terminate(term(), state_t()) -> term().
terminate(_Reason, _State) ->
    ok.

%% @private
-spec code_change(term() | {down, term()}, state_t(), term()) -> {ok, state_t()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @private
schedule_resend() ->
    timer:send_after(?WAIT_TIME_BEFORE_CHECK_RESEND, check_resend).