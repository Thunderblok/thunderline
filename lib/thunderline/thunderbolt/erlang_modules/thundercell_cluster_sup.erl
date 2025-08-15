%% THUNDERCELL Cluster Supervisor
%%
%% Manages multiple CA cell clusters with independent supervision trees.
%% Each cluster represents a 3D CA space with massive concurrent processing.

-module(thundercell_cluster_sup).

-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_cluster/1,
    stop_cluster/1,
    get_all_cluster_status/0,
    get_cluster_info/1
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a new CA cluster with specified configuration
start_cluster(ClusterConfig) ->
    ClusterId = maps:get(cluster_id, ClusterConfig, generate_cluster_id()),
    UpdatedConfig = ClusterConfig#{cluster_id => ClusterId},
    
    ChildSpec = #{
        id => ClusterId,
        start => {thundercell_cluster, start_link, [UpdatedConfig]},
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [thundercell_cluster]
    },
    
    case supervisor:start_child(?SERVER, ChildSpec) of
        {ok, ClusterPid} ->
            % Notify Thunderlane of new cluster
            thundercell_bridge:notify_cluster_status(ClusterId, {started, ClusterPid}),
            {ok, ClusterPid};
        Error ->
            Error
    end.

%% @doc Stop an existing CA cluster
stop_cluster(ClusterId) ->
    case supervisor:terminate_child(?SERVER, ClusterId) of
        ok ->
            supervisor:delete_child(?SERVER, ClusterId),
            thundercell_bridge:notify_cluster_status(ClusterId, stopped),
            ok;
        Error ->
            Error
    end.

%% @doc Get status of all active clusters
get_all_cluster_status() ->
    Children = supervisor:which_children(?SERVER),
    Status = lists:map(fun({ClusterId, ClusterPid, Type, _Modules}) ->
        case Type of
            supervisor ->
                ClusterInfo = get_cluster_detailed_info(ClusterPid),
                {ClusterId, ClusterInfo};
            _ ->
                {ClusterId, #{status => unknown, type => Type}}
        end
    end, Children),
    {ok, Status}.

%% @doc Get detailed information about a specific cluster
get_cluster_info(ClusterId) ->
    case supervisor:get_childspec(?SERVER, ClusterId) of
        {ok, #{start := {_M, _F, [Config]}}} ->
            % Get cluster configuration
            {ok, Config};
        {error, not_found} ->
            {error, cluster_not_found}
    end.

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },
    
    % No initial children - clusters are started dynamically
    ChildSpecs = [],
    
    {ok, {SupFlags, ChildSpecs}}.

%%====================================================================
%% Internal functions
%%====================================================================

generate_cluster_id() ->
    Timestamp = erlang:system_time(millisecond),
    Random = rand:uniform(1000),
    list_to_atom("cluster_" ++ integer_to_list(Timestamp) ++ "_" ++ integer_to_list(Random)).

get_cluster_detailed_info(ClusterPid) ->
    try
        % Get cluster statistics from the cluster process
        case gen_server:call(ClusterPid, get_cluster_stats) of
            {ok, Stats} ->
                Stats#{status => running, pid => ClusterPid};
            _ ->
                #{status => running, pid => ClusterPid, stats => unavailable}
        end
    catch
        _:_ ->
            #{status => unreachable, pid => ClusterPid}
    end.
