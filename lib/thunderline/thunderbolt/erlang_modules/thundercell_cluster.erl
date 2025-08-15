%% THUNDERCELL CA Cluster
%%
%% Individual CA cluster managing a 3D cellular automata space with
%% massive concurrent processing. Each cell is a separate Erlang process
%% for maximum concurrency and fault isolation.

-module(thundercell_cluster).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    evolve_generation/1,
    get_cluster_stats/1,
    get_cell_state/4,
    set_ca_rules/2,
    pause_evolution/1,
    resume_evolution/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    cluster_id,
    dimensions,           % {X, Y, Z} grid dimensions
    ca_rules,            % Current CA rules for evolution
    cell_processes,      % Map of {X,Y,Z} -> CellPid
    generation,          % Current generation number
    evolution_timer,     % Timer for automatic evolution
    evolution_interval,  % Milliseconds between generations
    paused = false,      % Evolution paused flag
    stats               % Performance statistics
}).

-define(DEFAULT_EVOLUTION_INTERVAL, 100).  % 100ms = 10 generations/second

%%====================================================================
%% API functions
%%====================================================================

start_link(ClusterConfig) ->
    ClusterId = maps:get(cluster_id, ClusterConfig),
    gen_server:start_link({local, ClusterId}, ?MODULE, ClusterConfig, []).

evolve_generation(ClusterId) ->
    gen_server:call(ClusterId, evolve_generation).

get_cluster_stats(ClusterId) ->
    gen_server:call(ClusterId, get_cluster_stats).

get_cell_state(ClusterId, X, Y, Z) ->
    gen_server:call(ClusterId, {get_cell_state, X, Y, Z}).

set_ca_rules(ClusterId, NewRules) ->
    gen_server:call(ClusterId, {set_ca_rules, NewRules}).

pause_evolution(ClusterId) ->
    gen_server:call(ClusterId, pause_evolution).

resume_evolution(ClusterId) ->
    gen_server:call(ClusterId, resume_evolution).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(ClusterConfig) ->
    process_flag(trap_exit, true),
    
    ClusterId = maps:get(cluster_id, ClusterConfig),
    Dimensions = maps:get(dimensions, ClusterConfig, {10, 10, 10}),
    CARules = maps:get(ca_rules, ClusterConfig, default_ca_rules()),
    EvolutionInterval = maps:get(evolution_interval, ClusterConfig, ?DEFAULT_EVOLUTION_INTERVAL),
    
    % Initialize all cell processes for the 3D grid
    CellProcesses = initialize_cell_grid(Dimensions, CARules),
    
    % Start evolution timer
    EvolutionTimer = erlang:send_after(EvolutionInterval, self(), evolve_generation),
    
    State = #state{
        cluster_id = ClusterId,
        dimensions = Dimensions,
        ca_rules = CARules,
        cell_processes = CellProcesses,
        generation = 0,
        evolution_timer = EvolutionTimer,
        evolution_interval = EvolutionInterval,
        stats = initialize_stats()
    },
    
    {ok, State}.

handle_call(evolve_generation, _From, State) ->
    {NewState, GenerationTime} = perform_evolution(State),
    Stats = update_stats(NewState#state.stats, GenerationTime),
    {reply, {ok, NewState#state.generation}, NewState#state{stats = Stats}};

handle_call(get_cluster_stats, _From, State) ->
    ClusterStats = #{
        cluster_id => State#state.cluster_id,
        dimensions => State#state.dimensions,
        generation => State#state.generation,
        paused => State#state.paused,
        cell_count => maps:size(State#state.cell_processes),
        performance => State#state.stats
    },
    {reply, {ok, ClusterStats}, State};

handle_call({get_cell_state, X, Y, Z}, _From, State) ->
    case maps:get({X, Y, Z}, State#state.cell_processes, undefined) of
        undefined ->
            {reply, {error, cell_not_found}, State};
        CellPid ->
            case thundercell_ca_cell:get_state(CellPid) of
                {ok, CellState} ->
                    {reply, {ok, CellState}, State};
                Error ->
                    {reply, Error, State}
            end
    end;

handle_call({set_ca_rules, NewRules}, _From, State) ->
    % Distribute new CA rules to all cells
    maps:map(fun(_Coord, CellPid) ->
        thundercell_ca_cell:set_rules(CellPid, NewRules)
    end, State#state.cell_processes),
    
    {reply, ok, State#state{ca_rules = NewRules}};

handle_call(pause_evolution, _From, State) ->
    case State#state.evolution_timer of
        undefined -> ok;
        Timer -> erlang:cancel_timer(Timer)
    end,
    {reply, ok, State#state{paused = true, evolution_timer = undefined}};

handle_call(resume_evolution, _From, State) ->
    case State#state.paused of
        true ->
            Timer = erlang:send_after(State#state.evolution_interval, self(), evolve_generation),
            {reply, ok, State#state{paused = false, evolution_timer = Timer}};
        false ->
            {reply, {error, not_paused}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(evolve_generation, State) ->
    case State#state.paused of
        true ->
            {noreply, State};
        false ->
            {NewState, GenerationTime} = perform_evolution(State),
            Stats = update_stats(NewState#state.stats, GenerationTime),
            
            % Schedule next evolution
            Timer = erlang:send_after(State#state.evolution_interval, self(), evolve_generation),
            
            {noreply, NewState#state{
                evolution_timer = Timer,
                stats = Stats
            }}
    end;

handle_info({'EXIT', CellPid, _Reason}, State) ->
    % Handle cell process crash - restart the cell
    case find_cell_coordinate(CellPid, State#state.cell_processes) of
        {ok, Coord} ->
            NewCellPid = restart_cell(Coord, State#state.ca_rules),
            NewCellProcesses = maps:put(Coord, NewCellPid, State#state.cell_processes),
            {noreply, State#state{cell_processes = NewCellProcesses}};
        not_found ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    % Clean shutdown of all cell processes
    maps:map(fun(_Coord, CellPid) ->
        thundercell_ca_cell:stop(CellPid)
    end, State#state.cell_processes),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

initialize_cell_grid({X, Y, Z}, CARules) ->
    maps:from_list([
        begin
            Coord = {Xi, Yi, Zi},
            CellPid = start_cell_process(Coord, CARules),
            {Coord, CellPid}
        end
        || Xi <- lists:seq(0, X-1),
           Yi <- lists:seq(0, Y-1),
           Zi <- lists:seq(0, Z-1)
    ]).

start_cell_process(Coord, CARules) ->
    {ok, CellPid} = thundercell_ca_cell:start_link(Coord, CARules),
    link(CellPid),
    CellPid.

restart_cell(Coord, CARules) ->
    start_cell_process(Coord, CARules).

perform_evolution(State) ->
    StartTime = erlang:monotonic_time(millisecond),
    
    % Phase 1: All cells calculate their next state based on neighbors
    maps:map(fun(Coord, CellPid) ->
        Neighbors = get_neighbor_states(Coord, State),
        thundercell_ca_cell:prepare_evolution(CellPid, Neighbors)
    end, State#state.cell_processes),
    
    % Phase 2: All cells simultaneously transition to their new state
    maps:map(fun(_Coord, CellPid) ->
        thundercell_ca_cell:commit_evolution(CellPid)
    end, State#state.cell_processes),
    
    EndTime = erlang:monotonic_time(millisecond),
    GenerationTime = EndTime - StartTime,
    
    NewGeneration = State#state.generation + 1,
    {State#state{generation = NewGeneration}, GenerationTime}.

get_neighbor_states({X, Y, Z}, State) ->
    NeighborCoords = get_3d_neighbors(X, Y, Z, State#state.dimensions),
    lists:map(fun(Coord) ->
        case maps:get(Coord, State#state.cell_processes, undefined) of
            undefined -> dead;  % Out of bounds cells are considered dead
            CellPid ->
                case thundercell_ca_cell:get_state(CellPid) of
                    {ok, CellState} -> CellState;
                    _ -> dead
                end
        end
    end, NeighborCoords).

get_3d_neighbors(X, Y, Z, {MaxX, MaxY, MaxZ}) ->
    [
        {Xi, Yi, Zi}
        || Xi <- [X-1, X, X+1],
           Yi <- [Y-1, Y, Y+1],
           Zi <- [Z-1, Z, Z+1],
           {Xi, Yi, Zi} =/= {X, Y, Z},  % Exclude self
           Xi >= 0, Xi < MaxX,
           Yi >= 0, Yi < MaxY,
           Zi >= 0, Zi < MaxZ
    ].

find_cell_coordinate(CellPid, CellProcesses) ->
    case maps:to_list(CellProcesses) of
        [] -> not_found;
        List ->
            case lists:keyfind(CellPid, 2, List) of
                {Coord, CellPid} -> {ok, Coord};
                false -> not_found
            end
    end.

default_ca_rules() ->
    #{
        name => "Conway's Game of Life 3D",
        birth_neighbors => [5, 6, 7],     % Neighbors needed for birth
        survival_neighbors => [4, 5, 6],  % Neighbors needed for survival
        neighbor_type => moore_3d          % 26-neighbor Moore neighborhood
    }.

initialize_stats() ->
    #{
        total_generations => 0,
        avg_generation_time => 0.0,
        min_generation_time => infinity,
        max_generation_time => 0,
        last_generation_time => 0
    }.

update_stats(Stats, GenerationTime) ->
    TotalGens = maps:get(total_generations, Stats) + 1,
    CurrentAvg = maps:get(avg_generation_time, Stats),
    NewAvg = (CurrentAvg * (TotalGens - 1) + GenerationTime) / TotalGens,
    
    Stats#{
        total_generations => TotalGens,
        avg_generation_time => NewAvg,
        min_generation_time => min(maps:get(min_generation_time, Stats), GenerationTime),
        max_generation_time => max(maps:get(max_generation_time, Stats), GenerationTime),
        last_generation_time => GenerationTime
    }.
