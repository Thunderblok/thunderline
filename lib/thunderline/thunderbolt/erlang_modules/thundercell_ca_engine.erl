%% THUNDERCELL CA Engine Manager
%%
%% High-level CA computation engine that coordinates multiple algorithms
%% and optimization strategies for cellular automata processing.

-module(thundercell_ca_engine).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    get_available_algorithms/0,
    optimize_rules/2,
    benchmark_performance/1,
    get_engine_status/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    algorithms = [],
    optimization_cache = #{},
    benchmark_history = [],
    engine_stats = #{}
}).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_available_algorithms() ->
    gen_server:call(?MODULE, get_algorithms).

optimize_rules(CARules, PerformanceTargets) ->
    gen_server:call(?MODULE, {optimize_rules, CARules, PerformanceTargets}).

benchmark_performance(ClusterConfig) ->
    gen_server:call(?MODULE, {benchmark, ClusterConfig}).

get_engine_status() ->
    gen_server:call(?MODULE, get_status).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        algorithms = initialize_algorithms(),
        optimization_cache = #{},
        benchmark_history = [],
        engine_stats = initialize_engine_stats()
    },
    {ok, State}.

handle_call(get_algorithms, _From, State) ->
    {reply, {ok, State#state.algorithms}, State};

handle_call({optimize_rules, CARules, PerformanceTargets}, _From, State) ->
    case optimize_ca_rules(CARules, PerformanceTargets, State) of
        {ok, OptimizedRules, NewState} ->
            {reply, {ok, OptimizedRules}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark, ClusterConfig}, _From, State) ->
    case run_benchmark(ClusterConfig, State) of
        {ok, BenchmarkResults, NewState} ->
            {reply, {ok, BenchmarkResults}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_status, _From, State) ->
    Status = #{
        algorithms => length(State#state.algorithms),
        cached_optimizations => maps:size(State#state.optimization_cache),
        benchmark_runs => length(State#state.benchmark_history),
        engine_stats => State#state.engine_stats
    },
    {reply, {ok, Status}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

initialize_algorithms() ->
    [
        #{
            name => "Conway's Game of Life 3D",
            birth_neighbors => [5, 6, 7],
            survival_neighbors => [4, 5, 6],
            description => "3D extension of Conway's classic Game of Life",
            complexity => medium
        },
        #{
            name => "Highlife 3D",
            birth_neighbors => [6, 8],
            survival_neighbors => [5, 6],
            description => "3D Highlife with different birth/survival rules",
            complexity => medium
        },
        #{
            name => "Seeds 3D",
            birth_neighbors => [4],
            survival_neighbors => [],
            description => "3D Seeds rule - cells die immediately after birth",
            complexity => low
        },
        #{
            name => "Maze 3D",
            birth_neighbors => [6],
            survival_neighbors => [3, 4, 5, 6, 7, 8],
            description => "3D Maze generation algorithm",
            complexity => high
        },
        #{
            name => "Custom Thunderline CA",
            birth_neighbors => [6, 7, 8],
            survival_neighbors => [5, 6, 7, 8],
            description => "Optimized CA rules for Thunderline architecture",
            complexity => medium
        }
    ].

initialize_engine_stats() ->
    #{
        optimizations_performed => 0,
        benchmarks_run => 0,
        total_clusters_processed => 0,
        avg_optimization_time => 0.0,
        cache_hit_ratio => 0.0
    }.

optimize_ca_rules(CARules, PerformanceTargets, State) ->
    % Check optimization cache first
    CacheKey = {CARules, PerformanceTargets},
    case maps:get(CacheKey, State#state.optimization_cache, undefined) of
        undefined ->
            % Perform new optimization
            case perform_optimization(CARules, PerformanceTargets) of
                {ok, OptimizedRules} ->
                    % Cache the result
                    NewCache = maps:put(CacheKey, OptimizedRules, State#state.optimization_cache),
                    NewStats = update_optimization_stats(State#state.engine_stats),
                    NewState = State#state{
                        optimization_cache = NewCache,
                        engine_stats = NewStats
                    },
                    {ok, OptimizedRules, NewState};
                Error ->
                    Error
            end;
        CachedResult ->
            % Return cached optimization
            {ok, CachedResult, State}
    end.

perform_optimization(CARules, PerformanceTargets) ->
    % Optimization algorithms based on performance targets
    TargetGenerationTime = maps:get(max_generation_time, PerformanceTargets, 100),
    _TargetConcurrency = maps:get(min_concurrency, PerformanceTargets, 1000),
    
    % Simple optimization: adjust neighbor requirements based on targets
    OptimizedRules = case TargetGenerationTime < 50 of
        true ->
            % Aggressive optimization for speed
            CARules#{
                birth_neighbors => [6, 7],      % Fewer birth conditions
                survival_neighbors => [5, 6],   % Fewer survival conditions
                optimization_level => high
            };
        false ->
            % Balanced optimization
            CARules#{
                optimization_level => medium
            }
    end,
    
    {ok, OptimizedRules}.

run_benchmark(ClusterConfig, State) ->
    % Create a temporary benchmark cluster
    BenchmarkId = generate_benchmark_id(),
    
    % Start benchmark cluster
    case thundercell_cluster_sup:start_cluster(ClusterConfig#{cluster_id => BenchmarkId}) of
        {ok, ClusterPid} ->
            % Run benchmark
            BenchmarkResults = execute_benchmark(BenchmarkId, ClusterPid),
            
            % Clean up benchmark cluster
            thundercell_cluster_sup:stop_cluster(BenchmarkId),
            
            % Update benchmark history
            NewHistory = [BenchmarkResults | State#state.benchmark_history],
            TrimmedHistory = lists:sublist(NewHistory, 50),  % Keep last 50 benchmarks
            
            NewStats = update_benchmark_stats(State#state.engine_stats),
            NewState = State#state{
                benchmark_history = TrimmedHistory,
                engine_stats = NewStats
            },
            
            {ok, BenchmarkResults, NewState};
        Error ->
            Error
    end.

execute_benchmark(BenchmarkId, _ClusterPid) ->
    StartTime = erlang:monotonic_time(millisecond),
    
    % Run 10 generations and measure performance
    GenerationTimes = [
        begin
            {ok, Generation} = thundercell_cluster:evolve_generation(BenchmarkId),
            EndTime = erlang:monotonic_time(millisecond),
            GenTime = EndTime - erlang:monotonic_time(millisecond),
            {Generation, GenTime}
        end
        || _ <- lists:seq(1, 10)
    ],
    
    EndTime = erlang:monotonic_time(millisecond),
    TotalTime = EndTime - StartTime,
    
    {ok, ClusterStats} = thundercell_cluster:get_cluster_stats(BenchmarkId),
    
    #{
        benchmark_id => BenchmarkId,
        total_time => TotalTime,
        generation_times => GenerationTimes,
        cluster_stats => ClusterStats,
        timestamp => erlang:system_time(millisecond)
    }.

generate_benchmark_id() ->
    Timestamp = erlang:system_time(millisecond),
    Random = rand:uniform(1000),
    list_to_atom("benchmark_" ++ integer_to_list(Timestamp) ++ "_" ++ integer_to_list(Random)).

update_optimization_stats(Stats) ->
    Count = maps:get(optimizations_performed, Stats) + 1,
    Stats#{optimizations_performed => Count}.

update_benchmark_stats(Stats) ->
    Count = maps:get(benchmarks_run, Stats) + 1,
    Stats#{benchmarks_run => Count}.
