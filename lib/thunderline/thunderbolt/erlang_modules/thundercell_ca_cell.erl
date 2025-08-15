%% THUNDERCELL CA Cell Process
%%
%% Individual cellular automaton cell process. Each cell maintains its own
%% state and applies CA rules based on neighbor information. Designed for
%% maximum concurrency with process-per-cell architecture.

-module(thundercell_ca_cell).

-behaviour(gen_server).

%% API
-export([
    start_link/2,
    get_state/1,
    set_rules/2,
    prepare_evolution/2,
    commit_evolution/1,
    stop/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    coordinate,           % {X, Y, Z} position in 3D grid
    current_state,        % Current cell state (alive/dead)
    next_state,          % Next cell state (prepared but not committed)
    ca_rules,            % CA rules for evolution
    generation,          % Current generation
    birth_time,          % When cell was born (if alive)
    stats                % Cell statistics
}).

-define(CELL_ALIVE, alive).
-define(CELL_DEAD, dead).

%%====================================================================
%% API functions
%%====================================================================

start_link(Coordinate, CARules) ->
    gen_server:start_link(?MODULE, {Coordinate, CARules}, []).

get_state(CellPid) ->
    gen_server:call(CellPid, get_state).

set_rules(CellPid, NewRules) ->
    gen_server:call(CellPid, {set_rules, NewRules}).

prepare_evolution(CellPid, NeighborStates) ->
    gen_server:cast(CellPid, {prepare_evolution, NeighborStates}).

commit_evolution(CellPid) ->
    gen_server:cast(CellPid, commit_evolution).

stop(CellPid) ->
    gen_server:call(CellPid, stop).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init({Coordinate, CARules}) ->
    State = #state{
        coordinate = Coordinate,
        current_state = random_initial_state(),
        next_state = undefined,
        ca_rules = CARules,
        generation = 0,
        birth_time = undefined,
        stats = initialize_cell_stats()
    },
    
    % Set birth time if initially alive
    FinalState = case State#state.current_state of
        ?CELL_ALIVE -> State#state{birth_time = erlang:system_time(millisecond)};
        _ -> State
    end,
    
    {ok, FinalState}.

handle_call(get_state, _From, State) ->
    CellInfo = #{
        coordinate => State#state.coordinate,
        state => State#state.current_state,
        generation => State#state.generation,
        birth_time => State#state.birth_time,
        stats => State#state.stats
    },
    {reply, {ok, CellInfo}, State};

handle_call({set_rules, NewRules}, _From, State) ->
    {reply, ok, State#state{ca_rules = NewRules}};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({prepare_evolution, NeighborStates}, State) ->
    % Calculate next state based on CA rules and neighbor states
    AliveNeighbors = count_alive_neighbors(NeighborStates),
    NextState = apply_ca_rules(State#state.current_state, AliveNeighbors, State#state.ca_rules),
    
    {noreply, State#state{next_state = NextState}};

handle_cast(commit_evolution, State) ->
    case State#state.next_state of
        undefined ->
            % No evolution prepared
            {noreply, State};
        NextState ->
            NewGeneration = State#state.generation + 1,
            
            % Update birth time if transitioning to alive
            NewBirthTime = case {State#state.current_state, NextState} of
                {?CELL_DEAD, ?CELL_ALIVE} -> erlang:system_time(millisecond);
                {?CELL_ALIVE, ?CELL_DEAD} -> undefined;
                _ -> State#state.birth_time
            end,
            
            % Update statistics
            NewStats = update_cell_stats(State#state.stats, State#state.current_state, NextState),
            
            NewState = State#state{
                current_state = NextState,
                next_state = undefined,
                generation = NewGeneration,
                birth_time = NewBirthTime,
                stats = NewStats
            },
            
            {noreply, NewState}
    end;

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

random_initial_state() ->
    % 20% chance of starting alive
    case rand:uniform(10) of
        N when N =< 2 -> ?CELL_ALIVE;
        _ -> ?CELL_DEAD
    end.

count_alive_neighbors(NeighborStates) ->
    lists:foldl(fun(#{state := ?CELL_ALIVE}, Count) -> Count + 1;
                   (?CELL_ALIVE, Count) -> Count + 1;
                   (_, Count) -> Count
                end, 0, NeighborStates).

apply_ca_rules(?CELL_DEAD, AliveNeighbors, CARules) ->
    % Dead cell - check birth conditions
    BirthNeighbors = maps:get(birth_neighbors, CARules, [5, 6, 7]),
    case lists:member(AliveNeighbors, BirthNeighbors) of
        true -> ?CELL_ALIVE;
        false -> ?CELL_DEAD
    end;

apply_ca_rules(?CELL_ALIVE, AliveNeighbors, CARules) ->
    % Alive cell - check survival conditions
    SurvivalNeighbors = maps:get(survival_neighbors, CARules, [4, 5, 6]),
    case lists:member(AliveNeighbors, SurvivalNeighbors) of
        true -> ?CELL_ALIVE;
        false -> ?CELL_DEAD
    end.

initialize_cell_stats() ->
    #{
        total_births => 0,
        total_deaths => 0,
        generations_alive => 0,
        generations_dead => 0,
        longest_life => 0,
        current_life_start => undefined
    }.

update_cell_stats(Stats, OldState, NewState) ->
    case {OldState, NewState} of
        {?CELL_DEAD, ?CELL_ALIVE} ->
            % Birth
            Stats#{
                total_births => maps:get(total_births, Stats) + 1,
                current_life_start => erlang:system_time(millisecond)
            };
        
        {?CELL_ALIVE, ?CELL_DEAD} ->
            % Death
            CurrentTime = erlang:system_time(millisecond),
            LifeStart = maps:get(current_life_start, Stats, CurrentTime),
            LifeLength = CurrentTime - LifeStart,
            
            Stats#{
                total_deaths => maps:get(total_deaths, Stats) + 1,
                longest_life => max(maps:get(longest_life, Stats), LifeLength),
                current_life_start => undefined
            };
        
        {?CELL_ALIVE, ?CELL_ALIVE} ->
            % Staying alive
            Stats#{
                generations_alive => maps:get(generations_alive, Stats) + 1
            };
        
        {?CELL_DEAD, ?CELL_DEAD} ->
            % Staying dead
            Stats#{
                generations_dead => maps:get(generations_dead, Stats) + 1
            }
    end.
