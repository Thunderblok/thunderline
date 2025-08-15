%% THUNDERCELL Telemetry and Performance Monitoring
%%
%% Collects and manages performance metrics for the THUNDERCELL compute layer.
%% Provides telemetry data to Thunderlane orchestration for monitoring.

-module(thundercell_telemetry).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start/0,
    get_compute_metrics/0,
    record_generation_time/2,
    record_cluster_event/2,
    get_performance_report/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    metrics = #{},
    start_time,
    collection_timer
}).

-define(COLLECTION_INTERVAL, 5000).  % 5 seconds

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:call(?MODULE, start_monitoring).

get_compute_metrics() ->
    gen_server:call(?MODULE, get_metrics).

record_generation_time(ClusterId, GenerationTime) ->
    gen_server:cast(?MODULE, {generation_time, ClusterId, GenerationTime}).

record_cluster_event(ClusterId, Event) ->
    gen_server:cast(?MODULE, {cluster_event, ClusterId, Event}).

get_performance_report() ->
    gen_server:call(?MODULE, get_performance_report).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        metrics = initialize_metrics(),
        start_time = erlang:system_time(millisecond)
    },
    {ok, State}.

handle_call(start_monitoring, _From, State) ->
    Timer = erlang:send_after(?COLLECTION_INTERVAL, self(), collect_metrics),
    {reply, ok, State#state{collection_timer = Timer}};

handle_call(get_metrics, _From, State) ->
    Metrics = prepare_metrics_for_thunderlane(State),
    {reply, {ok, Metrics}, State};

handle_call(get_performance_report, _From, State) ->
    Report = generate_performance_report(State),
    {reply, {ok, Report}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({generation_time, ClusterId, GenerationTime}, State) ->
    NewMetrics = update_generation_metrics(State#state.metrics, ClusterId, GenerationTime),
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({cluster_event, ClusterId, Event}, State) ->
    NewMetrics = update_cluster_event_metrics(State#state.metrics, ClusterId, Event),
    {noreply, State#state{metrics = NewMetrics}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(collect_metrics, State) ->
    % Collect system metrics
    SystemMetrics = collect_system_metrics(),
    NewMetrics = maps:merge(State#state.metrics, SystemMetrics),
    
    % Schedule next collection
    Timer = erlang:send_after(?COLLECTION_INTERVAL, self(), collect_metrics),
    
    {noreply, State#state{
        metrics = NewMetrics,
        collection_timer = Timer
    }};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    case State#state.collection_timer of
        undefined -> ok;
        Timer -> erlang:cancel_timer(Timer)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

initialize_metrics() ->
    #{
        cluster_metrics => #{},
        system_metrics => #{},
        performance_history => [],
        generation_stats => #{
            total_generations => 0,
            total_generation_time => 0,
            avg_generation_time => 0.0,
            min_generation_time => infinity,
            max_generation_time => 0
        }
    }.

update_generation_metrics(Metrics, ClusterId, GenerationTime) ->
    % Update cluster-specific metrics
    ClusterMetrics = maps:get(cluster_metrics, Metrics, #{}),
    ClusterStats = maps:get(ClusterId, ClusterMetrics, #{
        generations => 0,
        total_time => 0,
        avg_time => 0.0,
        min_time => infinity,
        max_time => 0
    }),
    
    NewGenerations = maps:get(generations, ClusterStats) + 1,
    NewTotalTime = maps:get(total_time, ClusterStats) + GenerationTime,
    NewAvgTime = NewTotalTime / NewGenerations,
    
    UpdatedClusterStats = ClusterStats#{
        generations => NewGenerations,
        total_time => NewTotalTime,
        avg_time => NewAvgTime,
        min_time => min(maps:get(min_time, ClusterStats), GenerationTime),
        max_time => max(maps:get(max_time, ClusterStats), GenerationTime),
        last_generation_time => GenerationTime
    },
    
    UpdatedClusterMetrics = ClusterMetrics#{ClusterId => UpdatedClusterStats},
    
    % Update global generation stats
    GlobalStats = maps:get(generation_stats, Metrics),
    GlobalGenerations = maps:get(total_generations, GlobalStats) + 1,
    GlobalTotalTime = maps:get(total_generation_time, GlobalStats) + GenerationTime,
    GlobalAvgTime = GlobalTotalTime / GlobalGenerations,
    
    UpdatedGlobalStats = GlobalStats#{
        total_generations => GlobalGenerations,
        total_generation_time => GlobalTotalTime,
        avg_generation_time => GlobalAvgTime,
        min_generation_time => min(maps:get(min_generation_time, GlobalStats), GenerationTime),
        max_generation_time => max(maps:get(max_generation_time, GlobalStats), GenerationTime)
    },
    
    Metrics#{
        cluster_metrics => UpdatedClusterMetrics,
        generation_stats => UpdatedGlobalStats
    }.

update_cluster_event_metrics(Metrics, ClusterId, Event) ->
    ClusterMetrics = maps:get(cluster_metrics, Metrics, #{}),
    ClusterStats = maps:get(ClusterId, ClusterMetrics, #{}),
    
    Events = maps:get(events, ClusterStats, []),
    Timestamp = erlang:system_time(millisecond),
    
    % Keep only last 100 events per cluster
    NewEvents = lists:sublist([{Timestamp, Event} | Events], 100),
    
    UpdatedClusterStats = ClusterStats#{events => NewEvents},
    UpdatedClusterMetrics = ClusterMetrics#{ClusterId => UpdatedClusterStats},
    
    Metrics#{cluster_metrics => UpdatedClusterMetrics}.

collect_system_metrics() ->
    #{
        system_metrics => #{
            timestamp => erlang:system_time(millisecond),
            memory_usage => erlang:memory(),
            process_count => erlang:system_info(process_count),
            schedulers => erlang:system_info(schedulers),
            scheduler_utilization => get_scheduler_utilization(),
            node_name => node(),
            uptime => get_uptime()
        }
    }.

get_scheduler_utilization() ->
    % Get scheduler utilization if available
    try
        erlang:statistics(scheduler_wall_time_all)
    catch
        _:_ -> undefined
    end.

get_uptime() ->
    {UpTime, _} = erlang:statistics(wall_clock),
    UpTime.

prepare_metrics_for_thunderlane(State) ->
    CurrentTime = erlang:system_time(millisecond),
    Uptime = CurrentTime - State#state.start_time,
    
    #{
        node => node(),
        timestamp => CurrentTime,
        uptime_ms => Uptime,
        thundercell_version => "1.0.0",
        metrics => State#state.metrics
    }.

generate_performance_report(State) ->
    Metrics = State#state.metrics,
    ClusterMetrics = maps:get(cluster_metrics, Metrics, #{}),
    GlobalStats = maps:get(generation_stats, Metrics),
    SystemMetrics = maps:get(system_metrics, Metrics, #{}),
    
    #{
        summary => #{
            total_clusters => maps:size(ClusterMetrics),
            total_generations => maps:get(total_generations, GlobalStats, 0),
            avg_generation_time => maps:get(avg_generation_time, GlobalStats, 0.0),
            node_uptime => get_uptime()
        },
        cluster_performance => ClusterMetrics,
        system_performance => SystemMetrics,
        generated_at => erlang:system_time(millisecond)
    }.
