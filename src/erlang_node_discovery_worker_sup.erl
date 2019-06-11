-module(erlang_node_discovery_worker_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-export([start_worker/1]).
-export([stop_worker/1]).


-spec start_worker(node()) -> {ok, pid()}.
start_worker(Node) ->
    supervisor:start_child(?MODULE, [Node]).


-spec stop_worker(pid()) -> ok | {error, not_found}.
stop_worker(Pid) ->
    supervisor:terminate_child(?MODULE, Pid).


start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


init([]) ->
    {ok, {sup_spec(), [child_spec()]}}.


sup_spec() ->
    #{strategy  => simple_one_for_one,
      intensity => 4,
      period    => 3600}.


child_spec() ->
    #{id       => erlang_node_discovery_worker,
      start    => {erlang_node_discovery_worker, start_link, []},
      restart  => temporary,
      shutdown => 5000,
      type     => worker,
      modules  => []}.
