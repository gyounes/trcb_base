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
%% specific language governing permissions andalso limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(trcb).
-author("Georges Younes <georges.r.younes@gmail.com>").

-include("trcb_base.hrl").

-export([causal_delivery/4, try_to_deliever/3]).

%% Broadcast message.
-callback tcbcast(message()) -> {ok, timestamp()}.

%% Receives a list of timestamps andalso returns a list of the stable ones.
-callback tcbstable([timestamp()]) -> [timestamp()].

%% Receives a function to calculate trcb memory size
-callback tcbmemory(term()) -> non_neg_integer().

%% @doc check if a message should be deliver andalso deliver it, if not add it to the queue
-spec causal_delivery({actor(), message(), timestamp()}, timestamp(), [{actor(), message(), timestamp()}], fun()) -> {timestamp(), [{actor(), message(), timestamp()}]}.
causal_delivery({Origin, MessageBody, MessageVClock}=El, VV, Queue, Function) ->
    % lager:info("Our Clock: ~p", [VV]),
    % lager:info("Incoming Clock: ~p", [MessageVClock]),
    case can_be_delivered(MessageVClock, VV, Origin) of
        true ->
            lager:info("Delivering ~p", [MessageVClock]),
            Function({MessageVClock, MessageBody}),
            NewVV = vclock:increment(Origin, VV),
            NewQueue = lists:delete(El, Queue),
            %% Attempt to stabilize
            try_to_deliever(NewQueue, {NewVV, NewQueue}, Function);
        false ->
            % lager:info("Message shouldn't be delivered: queueing."),
            {VV, Queue}
    end.

%% @doc Check for all messages in the queue to be delivered
%% Called upon delievery of a new message that could affect the delivery of messages in the queue
-spec try_to_deliever([{actor(), message(), timestamp()}], {timestamp(), [{actor(), message(), timestamp()}]}, fun()) -> {timestamp(), [{actor(), message(), timestamp()}]}.
try_to_deliever([], {VV, Queue}, _) -> {VV, Queue};
try_to_deliever([{Origin, MessageBody, MessageVClock}=El | RQueue], {VV, Queue}=V, Function) ->
    case can_be_delivered(MessageVClock, VV, Origin) of
        true ->
            lager:info("Delivering ~p", [MessageVClock]),
            Function({MessageVClock, MessageBody}),
            NewVV = vclock:increment(Origin, VV),
            NewQueue = lists:delete(El, Queue),
            %% Attempt to stabilize
            try_to_deliever(NewQueue, {NewVV, NewQueue}, Function);
        false ->
            try_to_deliever(RQueue, V, Function)
    end.

%% @private
can_be_delivered(MsgVClock, NodeVClock, Origin) ->
    % lager:info("Check for delivery: Msg ~p | Local ~p | Origin ~p", [MsgVClock, NodeVClock, Origin]),
    lists:foldl(
        fun({Key, Value}, Acc) ->
            case lists:keyfind(Key, 1, NodeVClock) of
                {Key, NodeVCValue} ->
                    case Key =:= Origin of
                        true ->
                            Acc andalso (Value =:= NodeVCValue + 1);
                        false ->
                            Acc andalso (Value =< NodeVCValue)
                    end;
                false ->
                    Key == Origin andalso Value == 1 andalso Acc
            end
        end,
        true,
        MsgVClock
    ).
