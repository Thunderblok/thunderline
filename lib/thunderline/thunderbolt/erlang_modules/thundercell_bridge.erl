%% THUNDERCELL Bridge to Thunderlane
%%
%% Provides communication interface between THUNDERCELL Erlang compute layer
%% and Thunderlane Elixir orchestration layer. Handles node discovery, 
%% RPC calls, and state synchronization.

-module(thundercell_bridge).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    init_thunderlane_connection/0,
    register_compute_node/0,
    disconnect_thunderlane/0,
    send_metrics_to_thunderlane/1,
    receive_ca_rules_from_thunderlane/0,
    notify_cluster_status/2
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    thunderlane_node = undefined,
    connection_status = disconnected,
    heartbeat_timer = undefined,
    metrics_timer = undefined
}).

-define(HEARTBEAT_INTERVAL, 30000).  % 30 seconds
-define(METRICS_INTERVAL, 10000).    % 10 seconds

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init_thunderlane_connection() ->
    gen_server:call(?MODULE, init_connection).

register_compute_node() ->
    gen_server:call(?MODULE, register_node).

disconnect_thunderlane() ->
    gen_server:call(?MODULE, disconnect).

send_metrics_to_thunderlane(Metrics) ->
    gen_server:cast(?MODULE, {send_metrics, Metrics}).

receive_ca_rules_from_thunderlane() ->
    gen_server:call(?MODULE, get_ca_rules).

notify_cluster_status(ClusterId, Status) ->
    gen_server:cast(?MODULE, {cluster_status, ClusterId, Status}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call(init_connection, _From, State) ->
    % Discover Thunderlane Elixir node
    case discover_thunderlane_node() of
        {ok, Node} ->
            case net_adm:ping(Node) of
                pong ->
                    HeartbeatTimer = erlang:send_after(?HEARTBEAT_INTERVAL, self(), heartbeat),
                    MetricsTimer = erlang:send_after(?METRICS_INTERVAL, self(), send_metrics),
                    NewState = State#state{
                        thunderlane_node = Node,
                        connection_status = connected,
                        heartbeat_timer = HeartbeatTimer,
                        metrics_timer = MetricsTimer
                    },
                    {reply, ok, NewState};
                pang ->
                    {reply, {error, connection_failed}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(register_node, _From, #state{thunderlane_node = Node} = State) when Node =/= undefined ->
    % Register this THUNDERCELL node with Thunderlane orchestration
    case rpc:call(Node, 'Elixir.Thunderlane.ErlangBridge', register_compute_node, [node()]) of
        {ok, registered} ->
            {reply, ok, State};
        Error ->
            {reply, {error, Error}, State}
    end;

handle_call(register_node, _From, State) ->
    {reply, {error, not_connected}, State};

handle_call(disconnect, _From, State) ->
    % Clean disconnect from Thunderlane
    case State#state.thunderlane_node of
        undefined -> ok;
        Node ->
            rpc:call(Node, 'Elixir.Thunderlane.ErlangBridge', unregister_compute_node, [node()])
    end,
    
    % Cancel timers
    cancel_timer(State#state.heartbeat_timer),
    cancel_timer(State#state.metrics_timer),
    
    NewState = State#state{
        thunderlane_node = undefined,
        connection_status = disconnected,
        heartbeat_timer = undefined,
        metrics_timer = undefined
    },
    {reply, ok, NewState};

handle_call(get_ca_rules, _From, #state{thunderlane_node = Node} = State) when Node =/= undefined ->
    % Fetch current CA rules from Thunderlane
    case rpc:call(Node, 'Elixir.Thunderlane.Resources.RuleSet', get_active_rules, []) of
        {ok, Rules} ->
            {reply, {ok, Rules}, State};
        Error ->
            {reply, {error, Error}, State}
    end;

handle_call(get_ca_rules, _From, State) ->
    {reply, {error, not_connected}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({send_metrics, Metrics}, #state{thunderlane_node = Node} = State) when Node =/= undefined ->
    % Send performance metrics to Thunderlane
    spawn(fun() ->
        rpc:cast(Node, 'Elixir.Thunderlane.MetricsCollector', receive_thundercell_metrics, [Metrics])
    end),
    {noreply, State};

handle_cast({cluster_status, ClusterId, Status}, #state{thunderlane_node = Node} = State) when Node =/= undefined ->
    % Notify Thunderlane of cluster status changes
    spawn(fun() ->
        rpc:cast(Node, 'Elixir.Thunderlane.HealthMonitor', receive_cluster_status, [ClusterId, Status])
    end),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(heartbeat, #state{thunderlane_node = Node} = State) when Node =/= undefined ->
    % Send heartbeat to Thunderlane
    case net_adm:ping(Node) of
        pong ->
            HeartbeatTimer = erlang:send_after(?HEARTBEAT_INTERVAL, self(), heartbeat),
            {noreply, State#state{heartbeat_timer = HeartbeatTimer}};
        pang ->
            % Connection lost, attempt reconnection
            {noreply, State#state{connection_status = disconnected}}
    end;

handle_info(send_metrics, State) ->
    % Collect and send metrics to Thunderlane
    Metrics = thundercell_telemetry:get_compute_metrics(),
    send_metrics_to_thunderlane(Metrics),
    MetricsTimer = erlang:send_after(?METRICS_INTERVAL, self(), send_metrics),
    {noreply, State#state{metrics_timer = MetricsTimer}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    % Clean up timers
    cancel_timer(State#state.heartbeat_timer),
    cancel_timer(State#state.metrics_timer),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

discover_thunderlane_node() ->
    % Discover Thunderlane Elixir node via various methods
    case os:getenv("THUNDERLANE_NODE") of
        false ->
            % Try default naming convention
            try_default_thunderlane_nodes();
        NodeStr ->
            Node = list_to_atom(NodeStr),
            {ok, Node}
    end.

try_default_thunderlane_nodes() ->
    % Try common Thunderlane node names
    PossibleNodes = [
        'thunderlane@localhost',
        'thunderlane@127.0.0.1',
        list_to_atom("thunderlane@" ++ net_adm:localhost())
    ],
    
    case find_reachable_node(PossibleNodes) of
        {ok, Node} -> {ok, Node};
        not_found -> {error, thunderlane_node_not_found}
    end.

find_reachable_node([]) ->
    not_found;
find_reachable_node([Node | Rest]) ->
    case net_adm:ping(Node) of
        pong -> {ok, Node};
        pang -> find_reachable_node(Rest)
    end.

cancel_timer(undefined) -> ok;
cancel_timer(Timer) -> erlang:cancel_timer(Timer).
