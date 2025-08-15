%% THUNDERCELL Main Supervisor
%% 
%% Top-level supervisor for the THUNDERCELL Erlang compute layer.
%% Manages cell cluster supervisors and core infrastructure processes.

-module(thundercell_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks  
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    
    ChildSpecs = [
        % Bridge to Thunderlane Elixir orchestration
        #{
            id => thundercell_bridge,
            start => {thundercell_bridge, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [thundercell_bridge]
        },
        
        % Telemetry and performance monitoring
        #{
            id => thundercell_telemetry,
            start => {thundercell_telemetry, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [thundercell_telemetry]
        },
        
        % CA Cell cluster supervisor
        #{
            id => thundercell_cluster_sup,
            start => {thundercell_cluster_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [thundercell_cluster_sup]
        },
        
        % CA computation engine manager
        #{
            id => thundercell_ca_engine,
            start => {thundercell_ca_engine, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [thundercell_ca_engine]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.
