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

-module(trcb_base).
-author("Georges Younes <georges.r.younes@gmail.com>").

-export([start/0,
         stop/0]).

%% API
-export([tcbdelivery/1,
         tcbgettagdetails/0,
         tcbcast/2,
         tcbstability/1,
         tcbmemory/1,
         tcbfullmembership/1,
         tcbstable/1]).

-include("trcb_base.hrl").

%% @doc Start the application.
start() ->
    application:ensure_all_started(trcb_base).

%% @doc Stop the application.
stop() ->
    application:stop(trcb_base).

%%%===================================================================
%%% API
%%%===================================================================

%% Set delivery Notification functoin.
-spec tcbdelivery(term()) -> ok.
tcbdelivery(Node) ->
    ?TCSB:tcbdelivery(Node).

%% Get Tag details.
-spec tcbgettagdetails() -> {vclock(), function()}.
tcbgettagdetails() ->
    ?TCSB:tcbgettagdetails().

%% Broadcast message.
-spec tcbcast(message(), vclock()) -> ok.
tcbcast(MessageBody, VV) ->
    ?TCSB:tcbcast(MessageBody, VV).

%% Configure the stability function.
-spec tcbstability(function()) -> ok.
tcbstability(StabilityFunction) ->
    ?TCSB:tcbstability(StabilityFunction).

%% Receives a function to calculate trcb memory size.
-spec tcbmemory(term()) -> non_neg_integer().
tcbmemory(CalcFunction) ->
    ?TCSB:tcbmemory(CalcFunction).

%% callback for setting fullmemberhsip of the group.
-spec tcbfullmembership(term()) -> ok.
tcbfullmembership(Nodes) ->
    ?TCSB:tcbfullmembership(Nodes).

%% Needed for testing to check if a list of
%% vvs are stable by comparing them to the SVV.
-spec tcbstable([timestamp()]) -> [timestamp()].
tcbstable(VVs) ->
    ?TCSB:tcbstable(VVs).