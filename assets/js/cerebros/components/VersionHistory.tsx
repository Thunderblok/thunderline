import React, { useState, useEffect } from 'react';
import { api, ModelArtifact, ModelRun } from '../api/client';

interface VersionHistoryProps {
  onRunSelect: (runId: string) => void;
}

export default function VersionHistory({ onRunSelect }: VersionHistoryProps) {
  const [artifacts, setArtifacts] = useState<ModelArtifact[]>([]);
  const [runs, setRuns] = useState<Record<string, ModelRun[]>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setLoading(true);
      const [artifactsData, runsData] = await Promise.all([
        api.getModelArtifacts(),
        api.getModelRuns()
      ]);

      setArtifacts(artifactsData);

      // Group runs by artifact ID
      const runsByArtifact: Record<string, ModelRun[]> = {};
      runsData.forEach((run) => {
        if (!runsByArtifact[run.model_artifact_id]) {
          runsByArtifact[run.model_artifact_id] = [];
        }
        runsByArtifact[run.model_artifact_id].push(run);
      });

      setRuns(runsByArtifact);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load data');
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (status: string) => {
    const badges = {
      pending: 'badge-warning',
      running: 'badge-info',
      completed: 'badge-success',
      errored: 'badge-error'
    };
    return badges[status as keyof typeof badges] || 'badge-neutral';
  };

  return (
    <div className="max-w-6xl mx-auto p-6">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-2xl font-bold">Model Version History</h2>
        <button onClick={loadData} className="btn btn-sm btn-outline" disabled={loading}>
          {loading ? <span className="loading loading-spinner"></span> : 'Refresh'}
        </button>
      </div>

      {error && (
        <div className="alert alert-error mb-4">
          <span>{error}</span>
        </div>
      )}

      {loading && artifacts.length === 0 ? (
        <div className="flex justify-center p-8">
          <span className="loading loading-spinner loading-lg"></span>
        </div>
      ) : (
        <div className="space-y-6">
          {artifacts.map((artifact) => (
            <div key={artifact.id} className="card bg-base-200">
              <div className="card-body">
                <div className="flex justify-between items-start">
                  <div>
                    <h3 className="card-title">Version {artifact.version}</h3>
                    <p className="text-sm opacity-70">{artifact.description}</p>
                    <p className="text-xs opacity-50 mt-1">
                      Created: {new Date(artifact.inserted_at).toLocaleString()}
                    </p>
                  </div>
                  <div className="badge badge-primary">
                    {runs[artifact.id]?.length || 0} runs
                  </div>
                </div>

                {runs[artifact.id] && runs[artifact.id].length > 0 && (
                  <div className="divider mt-2 mb-2"></div>
                )}

                {runs[artifact.id] && runs[artifact.id].length > 0 ? (
                  <div className="overflow-x-auto">
                    <table className="table table-sm">
                      <thead>
                        <tr>
                          <th>Run ID</th>
                          <th>Status</th>
                          <th>Started</th>
                          <th>Metrics</th>
                          <th>Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {runs[artifact.id].map((run) => (
                          <tr key={run.id} className="hover">
                            <td className="font-mono text-xs">{run.id.slice(0, 8)}</td>
                            <td>
                              <span className={`badge badge-sm ${getStatusBadge(run.status)}`}>
                                {run.status}
                              </span>
                            </td>
                            <td className="text-xs">
                              {new Date(run.started_at).toLocaleString()}
                            </td>
                            <td>
                              {run.metrics ? (
                                <span className="text-xs">
                                  {Object.keys(run.metrics).length} metrics
                                </span>
                              ) : (
                                <span className="text-xs opacity-50">N/A</span>
                              )}
                            </td>
                            <td>
                              <button
                                onClick={() => onRunSelect(run.id)}
                                className="btn btn-xs btn-primary"
                              >
                                View Details
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : (
                  <p className="text-sm opacity-50 text-center py-2">
                    No evaluation runs for this version yet
                  </p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {artifacts.length === 0 && !loading && (
        <div className="alert alert-info">
          <span>No model versions available. Create a model artifact to get started.</span>
        </div>
      )}
    </div>
  );
}
