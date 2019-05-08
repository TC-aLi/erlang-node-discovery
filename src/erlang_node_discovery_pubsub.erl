-module(erlang_node_discovery_pubsub).
-behavior(gen_server).

-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-export([start_link/0]).
-export([pub/0]).

-record(state, {
    sub_pid     :: pid(),
    sub_pchan   :: binary(),                       %% pattern channel
    pub_timer   :: reference() | once | undefined, %% timer
    pub_chan    :: binary(),                       %% channel
    pub_payload :: term(),
    pub_intvl   :: integer()
}).

-include("erlang_node_discovery.hrl").


-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-spec pub() -> pub.
pub() ->
    erlang:send(?MODULE, pub).


%% gen_server
init([]) ->
    {ok, init_pub(init_psub(#state{})), ?DEFAULT_PUB_DELAY}.


handle_call(Msg, _From, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {reply, ok, State}.


handle_cast(Msg, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


handle_info(timeout, State) ->
    State1 = psub(State),
    State2 = set_pub_timer(start, State1),
    publish(all, State2#state{pub_timer = once}),
    {noreply, State2};

handle_info(pub, State = #state{pub_payload = Payload}) ->
    State1 = set_pub_timer(case is_in_cluster(Payload) of true -> stop; false -> start end, State),
    publish(all, State1),
    {noreply, State1};

handle_info({subscribed, PChan, Pid}, State = #state{sub_pid = Pid}) ->
    lager:info("Channel subscribed ~p~n", [PChan]),
    eredis_sub:ack_message(Pid),
    {noreply, State};

handle_info({pmessage, PChan, _Chan, PL, Pid}, State = #state{sub_pid = Pid, sub_pchan = PChan, pub_payload = {Node, _}}) ->
    eredis_sub:ack_message(Pid),
    {To, {From, {Host, Port}}} = binary_to_term(PL),
    case To of
        all ->
            lager:info("Message received from ~p to ~p~n", [From, To]),
            add_node(From, Host, Port),
            From =/= Node andalso publish(From, State#state{pub_timer = once});
        Node ->
            lager:info("Message received from ~p to ~p ~n", [From, To]),
            add_node(From, Host, Port);
        _ ->
            lager:info("Message received from ~p to ~p ignored~n", [From, To]),
            ignore
    end,
    {noreply, State};

handle_info({eredis_disconnected, Pid}, State = #state{sub_pid = Pid}) ->
    lager:info("eredis disconnected ~p~n", [Pid]),
    eredis_sub:ack_message(Pid),
    {noreply, State};

handle_info({eredis_connected, Pid}, State = #state{sub_pid = Pid, sub_pchan = PChan}) ->
    lager:info("eredis connected ~p~n", [Pid]),
    eredis_sub:ack_message(Pid),
    eredis_sub:psubscribe(Pid, [PChan]),
    {noreply, State};

handle_info(Msg, State) ->
    lager:error("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_Old, State, _Extra) ->
    {ok, State}.


%% internal funcs
init_pub(State) ->
    Conf = application:get_all_env(erlang_node_discovery),
    DiscoveryPort = proplists:get_value(discovery_port, Conf, 0),
    ChannelPrefix = proplists:get_value(channel_prefix, Conf, ?DEFAULT_CHANNEL_PREFIX),
    ContainerName = proplists:get_value(container_name, Conf, ?DEFAULT_CONTAINER_NAME),
    PubInterval   = proplists:get_value(pub_interval,   Conf, ?DEFAULT_PUB_INTERVAL),
    Chan = list_to_binary(ChannelPrefix ++ atom_to_list(node())),
    Payload = {node(), {os:getenv(ContainerName), DiscoveryPort}},
    State#state{pub_chan = Chan, pub_payload = Payload, pub_intvl = PubInterval}.


init_psub(State) ->
    Conf = application:get_all_env(erlang_node_discovery),
    ChannelPrefix = proplists:get_value(channel_prefix, Conf, ?DEFAULT_CHANNEL_PREFIX),
    PChan = list_to_binary(ChannelPrefix ++ "*"),
    State#state{sub_pchan = PChan}.


psub(State = #state{sub_pchan = PChan}) ->
    RedisConf = application:get_all_env(erlang_node_discovery),
    RedisCluster = proplists:get_value(redis_cluster, RedisConf, node_discovery),
    Conf = proplists:get_value(list_to_atom(atom_to_list(RedisCluster) ++ "_1"), redis_config_manager:get_all_hosts(RedisCluster), []),
    Host = proplists:get_value(name, Conf, "127.0.0.1"),
    Port = proplists:get_value(port, Conf, 6379),
    {ok, Pid} = eredis_sub:start_link(Host, Port, ""),
    eredis_sub:controlling_process(Pid),
    eredis_sub:psubscribe(Pid, [PChan]),
    State#state{sub_pid = Pid}.


set_pub_timer(start, State = #state{pub_timer = Timer, pub_intvl = Intvl}) ->
    catch erlang:cancel_timer(Timer),
    NewTimer = erlang:send_after(Intvl, self(), pub),
    State#state{pub_timer = NewTimer};

set_pub_timer(stop, State = #state{pub_timer = Timer}) ->
    catch erlang:cancel_timer(Timer),
    State#state{pub_timer = undefined}.


publish(_To, #state{pub_timer = undefined}) ->
    ok;

publish(To, #state{pub_timer = Timer, pub_chan = Chan, pub_payload = Payload}) when is_reference(Timer) orelse Timer =:= once ->
    tt_redis:publish(pubsub, Chan, term_to_binary({To, Payload})).


add_node(From, Host, Port) ->
    not lists:member({From, {Host, Port}}, erlang_node_discovery_manager:list_nodes()) andalso
    erlang_node_discovery_manager:add_node(From, Host, Port).


is_in_cluster(Payload) ->
    case erlang_node_discovery_manager:list_nodes() of
        [] -> false;
        [Payload] -> false;
        L ->
            lists:member(Payload, L) andalso
            lists:any(fun erlang_node_discovery_manager:is_node_up/1, [Node || {Node, _} <- L -- [Payload]])
    end.
