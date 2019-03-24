-module(erlang_node_discovery_pubsub).
-behavior(gen_server).

-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-export([start_link/0]).
-export([pub/0, pub/3]).

-record(state, {
    sub_pid     :: pid(),
    sub_pchan   :: binary(),  %% patten channel
    pub_timer   :: any(),     %% timer reference
    pub_chan    :: binary(),  %% channel
    pub_payload :: binary(),
    pub_intvl   :: integer()
}).

-include("erlang_node_discovery.hrl").


-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-spec pub() -> ok.
pub() ->
    Conf = application:get_all_env(erlang_node_discovery),
    DiscoveryPort = proplists:get_value(discovery_port, Conf, 0),
    ChannelPrefix = proplists:get_value(channel_prefix, Conf, ?DEFAULT_CHANNEL_PREFIX),
    ContainerName = proplists:get_value(container_name, Conf, ?DEFAULT_CONTAINER_NAME),
    PubInterval   = proplists:get_value(pub_interval,   Conf, ?DEFAULT_PUB_INTERVAL),
    Chan = list_to_binary(ChannelPrefix ++ atom_to_list(node())),
    Payload = term_to_binary({node(), os:getenv(ContainerName), DiscoveryPort}),
    pub(Chan, Payload, PubInterval).

-spec pub(string(), term(), integer()) -> ok.
pub(Chan, Payload, Intvl) ->
    gen_server:call(?MODULE, {pub, Chan, Payload, Intvl}, infinity).


-spec psub() -> {pid(), binary()}.
psub() ->
    Conf = application:get_all_env(erlang_node_discovery),
    ChannelPrefix = proplists:get_value(channel_prefix, Conf, ?DEFAULT_CHANNEL_PREFIX),
    psub(list_to_binary(ChannelPrefix ++ "*")).

-spec psub(binary()) -> {pid(), binary()}.
psub(PChan) ->
    Conf = proplists:get_value(pubsub_1, redis_config_manager:get_all_hosts(pubsub), []),
    Host = proplists:get_value(name, Conf, "127.0.0.1"),
    Port = proplists:get_value(port, Conf, 6379),
    {ok, Pid} = eredis_sub:start_link(Host, Port, ""),
    eredis_sub:controlling_process(Pid),
    eredis_sub:psubscribe(Pid, [PChan]),
    {Pid, PChan}.


%% gen_server
init([]) ->
    {Pid, PChan} = psub(),
    {ok, #state{sub_pid = Pid, sub_pchan = PChan}}.


handle_call({pub, Chan, Payload, Intvl}, _From, State) ->
    Self = self(),
    Timer = erlang:send_after(0, Self, {pub, Self}),
    {reply, ok, State#state{pub_timer = Timer, pub_chan = Chan, pub_payload = Payload, pub_intvl = Intvl}};

handle_call(Msg, _From, State) ->
    io:format("Unexpected message: ~p~n", [Msg]),
    {reply, ok, State}.


handle_cast(Msg, State) ->
    io:format("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


handle_info({pub, From}, State = #state{pub_timer = Timer, pub_chan = Chan, pub_payload = Payload, pub_intvl = Intvl}) when From =:= self() ->
    erlang:cancel_timer(Timer),
    Self = self(),
    NewTimer = erlang:send_after(Intvl, Self, {pub, Self}),
    tt_redis:publish(pubsub, Chan, Payload),
    {noreply, State#state{pub_timer = NewTimer}};

handle_info(timeout, State = #state{sub_pchan = PChan}) ->
    io:format("timeout ~n"),
    {Pid, _} = psub(PChan),
    {noreply, State#state{sub_pid = Pid}};

handle_info({subscribed, _PChan, Pid} = Msg, State = #state{sub_pid = Pid}) ->
    io:format("Channel subscribed ~p~n", [Msg]),
    eredis_sub:ack_message(Pid),
    {noreply, State};

handle_info({pmessage, PChan, _Chan, Payload, Pid} = Msg, State = #state{sub_pid = Pid, sub_pchan = PChan}) ->
    io:format("Message received ~p~n", [Msg]),
    io:format("State is ~p~n", [State]),
    eredis_sub:ack_message(Pid),
    {Node, Host, Port} = binary_to_term(Payload),
    erlang_node_discovery_manager:add_node(Node, Host, Port),
    {noreply, State};

handle_info({eredis_disconnected, Pid}, State = #state{sub_pid = Pid}) ->
    io:format("eredis disconnected ~p~n", [Pid]),
    eredis_sub:ack_message(Pid),
    {noreply, State};

handle_info({eredis_connected, Pid}, State = #state{sub_pid = Pid, sub_pchan = PChan}) ->
    io:format("eredis connected ~p~n", [Pid]),
    eredis_sub:ack_message(Pid),
    eredis_sub:psubscribe(Pid, [PChan]),
    {noreply, State};

handle_info(Msg, State) ->
    io:format("Unexpected message: ~p~n", [Msg]),
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_Old, State, _Extra) ->
    {ok, State}.
