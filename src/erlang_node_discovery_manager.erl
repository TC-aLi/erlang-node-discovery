-module(erlang_node_discovery_manager).
-behaviour(gen_server).

-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-export([start_link/0]).
-export([add_node/3]).
-export([remove_node/1]).
-export([list_nodes/0]).
-export([is_node_up/0, is_node_up/1]).
-export([get_info/0]).

-record(state, {
    db_callback  :: module(), %% add_node/3, remove_node/1, list_nodes/0
    resolve_func :: fun((term()) -> term()),
    workers      :: map()     %% node -> worker_pid()
}).


-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-spec add_node(node(), inet:hostname(), inet:port_number()) -> ok.
add_node(Node, Host, Port) ->
    gen_server:call(?MODULE, {add_node, Node, Host, Port}, infinity).


-spec remove_node(node()) -> ok.
remove_node(Node) ->
    gen_server:call(?MODULE, {remove_node, Node}, infinity).


-spec list_nodes() -> [{node(), {inet:hostname(), inet:port_number()}}].
list_nodes() ->
    gen_server:call(?MODULE, list_nodes, infinity).


-spec is_node_up() -> [{node(), boolean()}].
is_node_up() ->
    gen_server:call(?MODULE, is_node_up, infinity).


-spec is_node_up(node()) -> boolean().
is_node_up(Node) ->
    gen_server:call(?MODULE, {is_node_up, Node}, infinity).


-spec get_info() -> Info when
      Info     :: [InfoElem],
      InfoElem :: {workers, [{node(), pid()}]}
                | {db_callback, module()}.
get_info() ->
    gen_server:call(?MODULE, get_info, infinity).


%% gen_server
init([]) ->
    Callback = application:get_env(erlang_node_discovery, db_callback, erlang_node_discovery_db),
    ResolveFunc =
    case application:get_env(erlang_node_discovery, resolve_func) of
        undefined -> fun(H) -> H end;
        {ok, F} when is_function(F, 1) -> F;
        {ok, {M, F}} -> fun M:F/1
    end,
    {ok, #state{workers = get_workers() , resolve_func = ResolveFunc, db_callback = Callback}}.


handle_call({add_node, Node, Host, Port}, _From, State = #state{db_callback = Callback, resolve_func = RF}) ->
    ok = Callback:add_node(Node, RF(Host), Port),
    {reply, ok, reinit_workers(State)};

handle_call({remove_node, Node}, _From, State = #state{db_callback = Callback}) ->
    ok = Callback:remove_node(Node),
    {reply, ok, reinit_workers(State)};

handle_call(list_nodes, _From, State = #state{db_callback = Callback}) ->
    {reply, Callback:list_nodes(), State};

handle_call({is_node_up, Node}, _From, State = #state{workers = Workers}) ->
    Reply =
    case maps:find(Node, Workers) of
        {ok, Pid} ->
            erlang_node_discovery_worker:is_node_up(Pid);
        error ->
            false
    end,
    {reply,Reply, State};

handle_call(is_node_up, _From, State = #state{workers = Workers}) ->
    Reply = [{Node, erlang_node_discovery_worker:is_node_up(Pid)} || {Node, Pid} <- maps:to_list(Workers)],
    {reply, Reply, State};

handle_call(get_info, _From, State = #state{workers = Workers, db_callback = Callback}) ->
    Info = [
        {workers, maps:to_list(Workers)},
        {db_callback, Callback}
    ],
    {reply, Info, State};

handle_call(Msg, _From, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {reply, {error, {bad_msg, Msg}}, State}.


handle_cast(Msg, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


handle_info({'DOWN', _Ref, _Type, Pid, Reason}, State) ->
    lager:info("Worker down with reason: ~p~n", [Reason]),
    {noreply, reinit_workers(worker_down(State, Pid))};

handle_info(Msg, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% internal funcs
-spec worker_down(State, Pid) -> NewState when
      State    :: #state{},
      Pid      :: pid(),
      NewState :: #state{}.
worker_down(State = #state{workers = Workers}, Pid) ->
    FoldFun = fun(Node, P, Acc) ->
        case P == Pid of
            true -> Acc;
            false -> Acc#{Node => P}
        end
    end,
    State#state{workers = maps:fold(FoldFun, #{}, Workers)}.


-spec reinit_workers(State) -> NewState when
      State    :: #state{},
      NewState :: #state{}.
reinit_workers(State) ->
    remove_workers(add_workers(State)).


-spec add_workers(State) -> NewState when
      State    :: #state{},
      NewState :: #state{}.
add_workers(State = #state{db_callback = Callback, workers = Workers}) ->
    FoldlFun = fun({Node, {_Host, _Port}}, TmpWorkers) ->
        case maps:find(Node, TmpWorkers) of
            error ->
                {ok, Pid} = erlang_node_discovery_worker_sup:start_worker(Node),
                erlang:monitor(process, Pid),
                lager:info("Started discovery worker for node ~s at ~p~n", [Node, Pid]),
                TmpWorkers#{Node => Pid};
            {ok, _} ->
                TmpWorkers
        end
    end,
    State#state{workers = lists:foldl(FoldlFun, Workers, Callback:list_nodes())}.


-spec remove_workers(State) -> NewState when
      State    :: #state{},
      NewState :: #state{}.
remove_workers(State = #state{db_callback = Callback, workers = Workers}) ->
    Nodes = [Node || {Node, {_Host, _Port}} <- Callback:list_nodes()],
    FoldFun = fun(Node, Pid, TmpWorkers) ->
        case lists:member(Node, Nodes) of
            true ->
                TmpWorkers#{Node => Pid};
            false ->
                ok = erlang_node_discovery_worker_sup:stop_worker(Pid),
                lager:info("Stopped discovery worker for node ~s at ~p~n", [Node, Pid]),
                TmpWorkers
        end
    end,
    State#state{workers = maps:fold(FoldFun, #{}, Workers)}.


get_workers() ->
   maps:from_list([{erlang_node_discovery_worker:get_node(Worker), Worker} || {_, Worker, _, _} <- supervisor:which_children(erlang_node_discovery_worker_sup)]).
