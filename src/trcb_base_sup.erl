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

-module(trcb_base_sup).
-author("Georges Younes <georges.r.younes@gmail.com>").

-behaviour(supervisor).

-include("trcb_base.hrl").

-export([start_link/0]).

-export([init/1]).

-define(CHILD(I, Type, Timeout),
        {I, {I, start_link, []}, permanent, Timeout, Type, [I]}).
-define(CHILD(I, Type), ?CHILD(I, Type, 5000)).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    configure(),

    TCSB = {trcb_base_tcsb,
               {trcb_base_tcsb, start_link, []},
               permanent, 5000, worker, [trcb_base_tcsb]},

    Resender = {trcb_base_resender,
                 {trcb_base_resender, start_link, []},
                 permanent, 5000, worker, [trcb_base_resender]},

    Children = [TCSB, Resender],

    RestartStrategy = {one_for_one, 10, 10},
    {ok, {RestartStrategy, Children}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
configure() ->
    %% configure metrics
    configure_var("LMETRICS",
                            lmetrics,
                            ?METRICS_DEFAULT).

%% @private
configure_var(Env, Var, Default) ->
    To = fun(V) -> atom_to_list(V) end,
    From = fun(V) -> list_to_atom(V) end,
    configure(Env, Var, Default, To, From).

%% @private
configure(Env, Var, Default, To, From) ->
    Current = trcb_base_config:get(Var, Default),
    Val = From(
        os:getenv(Env, To(Current))
    ),
    trcb_base_config:set(Var, Val),
    Val.
