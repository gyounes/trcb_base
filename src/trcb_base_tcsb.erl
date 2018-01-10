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

-module(trcb_base_tcsb).
-author("Georges Younes <georges.r.younes@gmail.com>").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% handler callbacks
-export([tcbcast/2,
         tcbmemory/1,
         tcbfullmembership/1]).

%% delivery callbacks
-export([tcbdelivery/1]).

%% stability callbacks
-export([tcbstability/1,
         tcbstable/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("trcb_base.hrl").

-record(state, {actor :: node(),
                metrics :: atom(),
                recv_cc :: causal_context:causal_context(),
                full_membership :: [{node(), integer()}],
                to_be_delv_queue :: [{actor(), message(), timestamp()}],
                gvv :: vclock:vclock(),
                delivery_function :: fun(),
                stability_function :: fun(),
                svv :: timestamp(),
                rtm :: timestamp_matrix()}).

-type state_t() :: #state{}.

%%%===================================================================
%%% handler callbacks
%%%===================================================================

%% callback for setting fullmemberhsip of the group.
-spec tcbfullmembership(term()) -> ok.
tcbfullmembership(Nodes) ->
    gen_server:call(?MODULE, {tcbfullmembership, Nodes}, infinity).

%% Broadcast message.
-spec tcbcast(message(), timestamp()) -> ok.
tcbcast(MessageBody, VV) ->
    gen_server:cast(?MODULE, {cbcast, MessageBody, VV}).

%% Receives a function to calculate trcb memory size
-spec tcbmemory(term()) -> non_neg_integer().
tcbmemory(CalcFunction) ->
    gen_server:call(?MODULE, {tcbmemory, CalcFunction}, infinity).

%% Configure the delivery function.
-spec tcbdelivery(function()) -> ok.
tcbdelivery(DeliveryFunction) ->
    gen_server:call(?MODULE, {tcbdelivery, DeliveryFunction}, infinity).

%% Configure the stability function.
-spec tcbstability(function()) -> ok.
tcbstability(StabilityFunction) ->
    gen_server:call(?MODULE, {tcbstability, StabilityFunction}, infinity).

%% Receives a list of timestamps and returns a list of the stable ones.
-spec tcbstable([timestamp()]) -> [timestamp()].
tcbstable(Timestamps) ->
    gen_server:call(?MODULE, {tcbstable, Timestamps}, infinity).

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
    DeliveryFun = fun(Msg) ->
        lager:info("Message delivered: ~p", [Msg]),
        ok
    end,

    StabilityFun = fun(Msg) ->
        lager:info("Message stabilized: ~p", [Msg]),
        ok
    end,

    init([DeliveryFun, StabilityFun]);
init([DeliveryFun, StabilityFun]) ->
    %% Seed the process at initialization.
    rand_compat:seed(erlang:phash2([node()]),
                     erlang:monotonic_time(),
                     erlang:unique_integer()),

    Actor = trcb_base_util:get_node(),

    %% Generate local dependency dots list.
    ToBeDelvQueue = [],

    %% Generate global version vector.
    GVV = vclock:fresh(),

    %% Generate local stable version vector.
    SVV = vclock:fresh(),

    %% Generate local recent timestamp matrix.
    RTM = mclock:fresh(),

    {ok, #state{actor=Actor,
                recv_cc=causal_context:new(),
                metrics=trcb_base_config:get(lmetrics),
                to_be_delv_queue=ToBeDelvQueue,
                gvv=GVV,
                svv=SVV,
                rtm=RTM,
                delivery_function=DeliveryFun,
                stability_function=StabilityFun,
                full_membership=[]}}.

%% @private
-spec handle_call(term(), {pid(), term()}, state_t()) ->
    {reply, term(), state_t()}.

handle_call({tcbdelivery, DeliveryFunction}, _From, State) ->
    {reply, ok, State#state{delivery_function=DeliveryFunction}};

handle_call({tcbstability, StabilityFunction}, _From, State) ->
    {reply, ok, State#state{stability_function=StabilityFunction}};

%% @todo Update other actors when this is changed
handle_call({tcbfullmembership, Nodes}, _From, State) ->
    Nodes1 = case lists:last(Nodes) of
        {_, _} ->
            [Node || {_Name, Node} <- Nodes];
        _ ->
            Nodes
    end,
    Sorted = lists:usort(Nodes1),
    OrderedNodes = [{lists:nth(X, Sorted), round(math:pow(2, length(Sorted)-X))} || X <- lists:seq(1, length(Sorted))],
    InitialVV = mclock:init_svv(OrderedNodes),
    RTM = mclock:init_rtm(OrderedNodes, InitialVV),
    % lager:info("tcbfullmembership is ~p", [OrderedNodes]),
    {reply, ok, State#state{full_membership=OrderedNodes, svv=InitialVV, rtm=RTM}};

handle_call({tcbmemory, CalcFunction}, _From, State) ->
    %% @todo fix
    %% calculate memory size
    Result = CalcFunction([]),
    {reply, Result, State};

handle_call({tcbstable, Timestamps}, _From, #state{svv=SVV}=State) ->
    %% check if Timestamp is stable
    StableTimestamps = lists:filter(fun(T) -> vclock:descends(SVV, T) end, Timestamps),
    {reply, StableTimestamps, State}.

%% @private
-spec handle_cast(term(), state_t()) -> {noreply, state_t()}.
handle_cast({cbcast, MessageBody, MessageVV},
            #state{actor=Actor,
                   metrics=Metrics,
                   stability_function=Fun,
                   rtm=RTM0,
                   full_membership=FullMembership}=State) ->

    %% measure time start local
    T1 = erlang:system_time(microsecond),

    Members = [X || {X, _} <- FullMembership],
    %% Only send to others without me to deliver
    %% as this message is already delievered
    ToMembers = trcb_base_util:without_me(Members),

    %% Generate message.
    %% @todo rmv Actor; could infer it from Dot
    Msg = {tcbcast, MessageVV, MessageBody, Actor},
    TaggedMsg = {?FIRST_TCBCAST_TAG, Msg},

    %% Add members to the queue of not ack messages
    Dot = {Actor, vclock:get_counter(Actor, MessageVV)},
    ?RESENDER:add_exactly_once_queue(Dot, {MessageVV, MessageBody, ToMembers}),

    %% Transmit to membership.
    trcb_base_util:send(TaggedMsg, ToMembers, Metrics, ?TCSB),

    %% measure time end local
    T2 = erlang:system_time(microsecond),

    %% record latency creating this message
    case Metrics of
        true ->
            lmetrics:record_latency(local, T2-T1);
        false ->
            ok
    end,

    %% Update the Recent Timestamp Matrix.
    RTM = mclock:update_rtm(RTM0, Actor, MessageVV),

    %% Update the Stable Version Vector.
    SVV = mclock:update_stablevv(RTM, Fun),

    {noreply, State#state{rtm=RTM, svv=SVV}};

handle_cast({tcbcast, MessageVV, MessageBody, MessageActor},
            #state{actor=Actor,
                   metrics=Metrics,
                   recv_cc=RecvCC0,
                   gvv=GVV0,
                   delivery_function=DeliveryFun,
                   to_be_delv_queue=ToBeDelvQueue0}=State) ->
    %% measure time start remote
    T1 = erlang:system_time(microsecond),

    Dot = {MessageActor, vclock:get_counter(MessageActor, MessageVV)},
    {RecvCC, GVV, ToBeDelvQueue} = case causal_context:is_element(Dot, RecvCC0) of
        true ->
            %% Already seen, do nothing.
            lager:info("Ignoring duplicate message from cycle, but send ack."),

            %% In some cases (e.g. ring with 3 participants), more than one node would
            %% be sending the same message. If a message was seen from one it should
            %% be ignored but an ack should be sent to the sender or it will be
            %% resent by that sender forever

            {RecvCC0, GVV0, ToBeDelvQueue0};
        false ->
            %% Check if the message should be delivered and delivers it or not.
            {GVV1, ToBeDelvQueue1} = trcb:causal_delivery({MessageActor, MessageBody, MessageVV},
                GVV0,
                [{MessageActor, MessageBody, MessageVV} | ToBeDelvQueue0],
                DeliveryFun),

            {causal_context:add_dot(Dot, RecvCC0), GVV1, ToBeDelvQueue1}
    end,
    %% measure time end remote
    T2 = erlang:system_time(microsecond),

    %% Generate message.
    MessageAck = {tcbcast_ack, Dot, Actor},
    TaggedMessageAck = {ack, MessageAck},

    %% Send ack back to message sender.
    trcb_base_util:send(TaggedMessageAck, MessageActor, Metrics, ?RESENDER),

    %% record latency creating this message
    case Metrics of
        true ->
            lmetrics:record_latency(remote, T2-T1);
        false ->
            ok
    end,
    {noreply, State#state{recv_cc=RecvCC, gvv=GVV, to_be_delv_queue=ToBeDelvQueue}};

handle_cast(Msg, State) ->
    lager:warning("Unhandled cast messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec handle_info(term(), state_t()) -> {noreply, state_t()}.
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

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% TODO trcb
%% For joins and leave only add to membership when message of joining is delivered, same for leaving
%% After doing that cast update stability bits (add, rmv) in STBAILIZER