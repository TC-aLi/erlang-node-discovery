-module(erlang_node_discovery_db).
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

-record(state, {
    nodes = #{} :: map()
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


-spec list_nodes() -> [{node(), inet:hostname(), inet:port_number()}].
list_nodes() ->
    gen_server:call(?MODULE, list_nodes, infinity).


%% gen_server
init([]) ->
    {ok, #state{}}.


handle_call({add_node, Node, Host, Port}, _From, State = #state{nodes = Nodes}) ->
    {reply, ok, State#state{nodes = Nodes#{Node => {Host, Port}}}};

handle_call({remove_node, Node}, _From, State) ->
    {reply, ok, State#state{nodes = maps:remove(Node, State#state.nodes)}};

handle_call(list_nodes, _From, State) ->
    {reply, maps:to_list(State#state.nodes), State};

handle_call(Msg, _From, State) ->
    error_logger:error_msg("Unexpected message: ~p~n", [Msg]),
    {reply, {error, {bad_msg, Msg}}, State}.


handle_cast(Msg, State) ->
    error_logger:error_msg("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


handle_info(Msg, State) ->
    error_logger:error_msg("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_Old, State, _Extra) ->
    {ok, State}.
