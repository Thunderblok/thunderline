import React, { useState, useEffect } from 'react';
import { api, ModelRun, Feedback } from '../api/client';
import { useLLMOutput } from '@llm-ui/react';
import { markdownLookBack } from '@llm-ui/markdown';
import { codeBlockLookBack } from '@llm-ui/code';
import ReactMarkdown from 'react-markdown';

interface RunDetailsProps {
  runId: string;
  onBack: () => void;
}

export default function RunDetails({ runId, onBack }: RunDetailsProps) {
  const [run, setRun] = useState<ModelRun | null>(null);
  const [feedbacks, setFeedbacks] = useState<Feedback[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Feedback form state
  const [feedbackRating, setFeedbackRating] = useState<number>(5);
  const [feedbackComment, setFeedbackComment] = useState<string>('');
  const [submittingFeedback, setSubmittingFeedback] = useState(false);

  useEffect(() => {
    loadRunDetails();
  }, [runId]);

  const loadRunDetails = async () => {
    try {
      setLoading(true);
      const [runData, feedbackData] = await Promise.all([
        api.getModelRun(runId),
        api.getFeedbackForRun(runId)
      ]);
      setRun(runData);
      setFeedbacks(feedbackData);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load run details');
    } finally {
      setLoading(false);
    }
  };

  const handleSubmitFeedback = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      setSubmittingFeedback(true);
      const feedback = await api.createFeedback({
        model_run_id: runId,
        comment: feedbackComment,
        rating: feedbackRating
      });
      setFeedbacks([...feedbacks, feedback]);
      setFeedbackComment('');
      setFeedbackRating(5);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to submit feedback');
    } finally {
      setSubmittingFeedback(false);
    }
  };

  const getStatusColor = (status: string) => {
    const colors = {
      pending: 'text-warning',
      running: 'text-info',
      completed: 'text-success',
      errored: 'text-error'
    };
    return colors[status as keyof typeof colors] || 'text-neutral';
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <span className="loading loading-spinner loading-lg"></span>
      </div>
    );
  }

  if (error || !run) {
    return (
      <div className="max-w-4xl mx-auto p-6">
        <div className="alert alert-error">
          <span>{error || 'Run not found'}</span>
        </div>
        <button onClick={onBack} className="btn btn-ghost mt-4">
          ← Back
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto p-6">
      <button onClick={onBack} className="btn btn-ghost btn-sm mb-4">
        ← Back to History
      </button>

      <div className="space-y-6">
        {/* Run Status Card */}
        <div className="card bg-base-200">
          <div className="card-body">
            <div className="flex justify-between items-start">
              <div>
                <h2 className="card-title">
                  Run Details
                  <span className={`badge ${getStatusColor(run.status)}`}>
                    {run.status.toUpperCase()}
                  </span>
                </h2>
                <p className="text-sm opacity-70 mt-2">ID: {run.id}</p>
                <p className="text-sm opacity-70">
                  Started: {new Date(run.started_at).toLocaleString()}
                </p>
                <p className="text-sm opacity-70">
                  Last Updated: {new Date(run.updated_at).toLocaleString()}
                </p>
              </div>
              <button
                onClick={loadRunDetails}
                className="btn btn-sm btn-outline"
                disabled={loading}
              >
                Refresh
              </button>
            </div>
          </div>
        </div>

        {/* Metrics Card */}
        {run.metrics && Object.keys(run.metrics).length > 0 && (
          <div className="card bg-base-200">
            <div className="card-body">
              <h3 className="card-title">Evaluation Metrics</h3>
              <div className="overflow-x-auto">
                <table className="table table-zebra">
                  <thead>
                    <tr>
                      <th>Metric</th>
                      <th>Value</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(run.metrics).map(([key, value]) => (
                      <tr key={key}>
                        <td className="font-semibold">{key}</td>
                        <td className="font-mono">
                          {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        {/* Model Output Card */}
        {run.status === 'completed' && (
          <div className="card bg-base-200">
            <div className="card-body">
              <h3 className="card-title">Model Output</h3>
              <div className="prose max-w-none">
                {/* Use LLM UI for rendering model outputs */}
                <div className="bg-base-100 p-4 rounded-lg">
                  <ReactMarkdown>
                    {run.metrics?.output || 'No output available'}
                  </ReactMarkdown>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Existing Feedback */}
        {feedbacks.length > 0 && (
          <div className="card bg-base-200">
            <div className="card-body">
              <h3 className="card-title">User Feedback ({feedbacks.length})</h3>
              <div className="space-y-3">
                {feedbacks.map((feedback) => (
                  <div key={feedback.id} className="bg-base-100 p-4 rounded-lg">
                    <div className="flex items-center gap-2 mb-2">
                      <div className="rating rating-sm">
                        {[1, 2, 3, 4, 5].map((star) => (
                          <input
                            key={star}
                            type="radio"
                            className="mask mask-star-2 bg-orange-400"
                            checked={star === feedback.rating}
                            disabled
                          />
                        ))}
                      </div>
                      <span className="text-sm opacity-70">
                        {new Date(feedback.inserted_at).toLocaleString()}
                      </span>
                    </div>
                    <p className="text-sm">{feedback.comment}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Feedback Form */}
        {run.status === 'completed' && (
          <div className="card bg-base-200">
            <div className="card-body">
              <h3 className="card-title">Submit Feedback</h3>
              <form onSubmit={handleSubmitFeedback} className="space-y-4">
                <div className="form-control">
                  <label className="label">
                    <span className="label-text">Rating</span>
                  </label>
                  <div className="rating rating-lg">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <input
                        key={star}
                        type="radio"
                        name="rating"
                        className="mask mask-star-2 bg-orange-400"
                        checked={star === feedbackRating}
                        onChange={() => setFeedbackRating(star)}
                      />
                    ))}
                  </div>
                </div>

                <div className="form-control">
                  <label className="label">
                    <span className="label-text">Comment</span>
                  </label>
                  <textarea
                    className="textarea textarea-bordered h-24"
                    placeholder="Share your thoughts on this evaluation..."
                    value={feedbackComment}
                    onChange={(e) => setFeedbackComment(e.target.value)}
                    required
                  ></textarea>
                </div>

                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={submittingFeedback || !feedbackComment.trim()}
                >
                  {submittingFeedback ? (
                    <>
                      <span className="loading loading-spinner"></span>
                      Submitting...
                    </>
                  ) : (
                    'Submit Feedback'
                  )}
                </button>
              </form>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
