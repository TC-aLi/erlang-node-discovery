-module(erlang_node_discovery).

-export([add_node/2, add_node/3]).
-export([remove_node/1]).
-export([list_nodes/0]).
-export([get_node_status/0, get_node_status/1]).


-spec add_node(node(), inet:port_number()) -> ok.
add_node(Node, Port) ->
    [_NodeName, Host] = string:tokens(atom_to_list(Node), "@"),
    add_node(Node, Host, Port).


-spec add_node(Node, Host, Port) -> ok when
      Node :: node(),
      Host :: inet:hostname(),
      Port :: inet:port_number().
add_node(Node, Host, Port) ->
    erlang_node_discovery_manager:add_node(Node, Host, Port).


-spec remove_node(node()) -> ok.
remove_node(Node) ->
    erlang_node_discovery_manager:remove_node(Node).


-spec list_nodes() -> [{node(), {inet:hostname(), inet:port_number()}}].
list_nodes() ->
    erlang_node_discovery_manager:list_nodes().


-spec get_node_status() -> [{node(), boolean()}].
get_node_status() ->
    erlang_node_discovery_manager:get_node_status().


-spec get_node_status(node()) -> boolean().
get_node_status(Node) ->
    erlang_node_discovery_manager:get_node_status(Node).
