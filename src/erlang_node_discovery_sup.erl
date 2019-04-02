-module(erlang_node_discovery_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).


start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


init([]) ->
    WorkersSup     = child_spec(erlang_node_discovery_worker_sup, supervisor),
    WorkersManager = child_spec(erlang_node_discovery_manager,    worker),
    PubsubClient   = child_spec(erlang_node_discovery_pubsub,     worker),
    {ok, {sup_spec(), [WorkersSup, WorkersManager, PubsubClient]}}.


sup_spec() ->
    #{strategy  => one_for_one,
      intensity => 4,
      period    => 3600}.


child_spec(Mod, Type) ->
    #{id       => Mod,
      start    => {Mod, start_link, []},
      restart  => permanent,
      shutdown => 5000,
      type     => Type,
      modules  => [Mod]}.
