%% THUNDERCELL Application
%%
%% Main OTP Application for THUNDERCELL Erlang compute layer
%% Provides massive concurrent CA processing with bridge to Thunderlane

-module(thundercell_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    lager:info("Starting THUNDERCELL application"),
    
    %% Initialize Mnesia if not already running
    case mnesia:system_info(is_running) of
        no -> 
            lager:info("Initializing Mnesia database"),
            mnesia:create_schema([node()]),
            mnesia:start();
        yes -> 
            lager:info("Mnesia already running")
    end,
    
    %% Start telemetry early
    ok = thundercell_telemetry:init(),
    
    %% Start the top-level supervisor
    case thundercell_sup:start_link() of
        {ok, Pid} ->
            lager:info("THUNDERCELL started successfully with supervisor ~p", [Pid]),
            {ok, Pid};
        Error ->
            lager:error("Failed to start THUNDERCELL: ~p", [Error]),
            Error
    end.

stop(_State) ->
    lager:info("Stopping THUNDERCELL application"),
    
    %% Clean shutdown of telemetry
    thundercell_telemetry:cleanup(),
    
    lager:info("THUNDERCELL stopped successfully"),
    ok.
