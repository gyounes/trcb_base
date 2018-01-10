%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Georges Younes, Inc.  All Rights Reserved.
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

%% @doc A simple Erlang implementation of matrix clocks not used exactly as Matrix clock
%% but as Recent Timestamp Matrix RTM as in referenced below:
%%
%% @reference Carlos Baquero, Paulo Sérgio Almeida, and Ali Shoker
%%      Making Operation-based CRDTs Operation-based (2014)
%%      [http://haslab.uminho.pt/ashoker/files/opbaseddais14.pdf]

-module(mclock).
-author("Georges Younes <georges.r.younes@gmail.com>").

-include("trcb_base.hrl").

-export([fresh/0, update_rtm/3, update_stablevv/2, init_rtm/2, init_svv/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export_type([mclock/0, mclock_node/0]).

-type mclock() :: [mc_entry()].
% The timestamp is present but not used, in case a client wishes to inspect it.
-type mc_entry() :: {mclock_node(), vclock:vclock()}.
% Nodes can have any term() as a name, but they must differ from each other.
-type mclock_node() :: term().

% @doc Create a brand new mclock.
-spec fresh() -> mclock().
fresh() ->
    [].

-spec update_rtm(mclock(), actor(), vclock:vclock()) -> mclock().
update_rtm(RTM, MsgActor, MsgVV) ->
    case lists:keymember(MsgActor, 1, RTM) of
        true ->
            lists:keyreplace(MsgActor, 1, RTM, {MsgActor, MsgVV});
        false ->
            [{MsgActor, MsgVV} | RTM]
    end.

-spec init_rtm([actor()], vclock:vclock()) -> mclock().
init_rtm(MsgActors, InitVV) ->
    lists:foldl(
        fun({Actor, _}, Acc) ->
            [{Actor, InitVV} | Acc]
        end,
        [],
        MsgActors).

-spec init_svv([actor()]) -> vclock:vclock().
init_svv(MsgActors) ->
    lists:foldl(
        fun({Actor, _}, Acc) ->
            [{Actor, 0} | Acc]
        end,
        [],
        MsgActors).

-spec update_stablevv(mclock(), fun()) -> vclock:vclock().
update_stablevv(RTM0, _Fun) ->
    [{_, Min0} | RTM1] = RTM0,

    lists:foldl(
        fun({_, VV}, Acc) ->
            lists:foldl(
                fun({Actor, Count}, Acc2) ->
                    case Count < vclock:get_counter(Actor, Acc2) of
                        true ->
                            % Fun({Actor, Count}),
                            lists:keyreplace(Actor, 1, Acc2, {Actor, Count});
                        false ->
                            Acc2
                    end
                end,
                Acc,
                VV
            )
        end,
        Min0,
        RTM1
    ).

%% ===================================================================
%% EUnit tests
%% ===================================================================
-ifdef(TEST).

% doc Serves as both a trivial test and some example code.
update_rtm_test() ->
    RTM = [{<<"1">>, [{<<"1">>, 1}, {<<"2">>, 2}]},
           {<<"2">>, [{<<"1">>, 3}, {<<"2">>, 4}]}],
    VV = [{<<"1">>, 5},
          {<<"2">>, 6}],
    ?assertEqual([{<<"1">>, [{<<"1">>, 5}, {<<"2">>, 6}]},
        {<<"2">>, [{<<"1">>, 3}, {<<"2">>, 4}]}], update_rtm(RTM, <<"1">>, VV)),
    ?assertEqual([{<<"1">>, [{<<"1">>, 1}, {<<"2">>, 2}]},
        {<<"2">>, [{<<"1">>, 5}, {<<"2">>, 6}]}], update_rtm(RTM, <<"2">>, VV)).

update_stablevv_test() ->
    RTM0 = [{<<"1">>, [{<<"1">>, 1}, {<<"2">>, 2}]},
           {<<"2">>, [{<<"1">>, 3}, {<<"2">>, 2}]}],
    RTM1 = [{<<"1">>, [{<<"1">>, 4}, {<<"2">>, 6}]},
           {<<"2">>, [{<<"1">>, 2}, {<<"2">>, 5}]}],
    StabilityFun = fun(Msg) ->
        lager:warning("Message Stablized: ~p", [Msg]),
        ok
    end,
    ?assertEqual([{<<"1">>, 1}, {<<"2">>, 2}], update_stablevv(RTM0, StabilityFun)),
    ?assertEqual([{<<"1">>, 2}, {<<"2">>, 5}], update_stablevv(RTM1, StabilityFun)).

-endif.
