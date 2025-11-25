import React, { useState, useEffect } from 'react';
import { api, ModelArtifact } from '../api/client';

interface ModelEvaluationProps {
  onRunCreated: (runId: string) => void;
}

export default function ModelEvaluation({ onRunCreated }: ModelEvaluationProps) {
  const [artifacts, setArtifacts] = useState<ModelArtifact[]>([]);
  const [selectedArtifactId, setSelectedArtifactId] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadArtifacts();
  }, []);

  const loadArtifacts = async () => {
    try {
      setLoading(true);
      const data = await api.getModelArtifacts();
      setArtifacts(data);
      if (data.length > 0) {
        setSelectedArtifactId(data[0].id);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load models');
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedArtifactId) {
      setError('Please select a model');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      const run = await api.createModelRun({ model_artifact_id: selectedArtifactId });
      onRunCreated(run.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create evaluation run');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto p-6">
      <h2 className="text-2xl font-bold mb-6">Start Model Evaluation</h2>

      {error && (
        <div className="alert alert-error mb-4">
          <span>{error}</span>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="form-control">
          <label className="label">
            <span className="label-text">Select Model Version</span>
          </label>
          <select
            className="select select-bordered w-full"
            value={selectedArtifactId}
            onChange={(e) => setSelectedArtifactId(e.target.value)}
            disabled={loading}
          >
            {artifacts.map((artifact) => (
              <option key={artifact.id} value={artifact.id}>
                v{artifact.version} - {artifact.description}
              </option>
            ))}
          </select>
        </div>

        {selectedArtifactId && (
          <div className="card bg-base-200 p-4">
            <h3 className="font-semibold mb-2">Model Details</h3>
            {artifacts.find((a) => a.id === selectedArtifactId) && (
              <div className="text-sm space-y-1">
                <p>
                  <strong>Version:</strong>{' '}
                  {artifacts.find((a) => a.id === selectedArtifactId)?.version}
                </p>
                <p>
                  <strong>Description:</strong>{' '}
                  {artifacts.find((a) => a.id === selectedArtifactId)?.description}
                </p>
                <p>
                  <strong>Created:</strong>{' '}
                  {new Date(
                    artifacts.find((a) => a.id === selectedArtifactId)?.inserted_at || ''
                  ).toLocaleString()}
                </p>
              </div>
            )}
          </div>
        )}

        <button
          type="submit"
          className="btn btn-primary w-full"
          disabled={loading || !selectedArtifactId}
        >
          {loading ? (
            <>
              <span className="loading loading-spinner"></span>
              Creating Run...
            </>
          ) : (
            'Start Evaluation'
          )}
        </button>
      </form>

      {artifacts.length === 0 && !loading && (
        <div className="alert alert-info mt-4">
          <span>No model versions available. Please create a model artifact first.</span>
        </div>
      )}
    </div>
  );
}
