// API Client for Cerebros Backend (Ash Framework)

interface ModelArtifact {
  id: string;
  version: string;
  description: string;
  inserted_at: string;
  updated_at: string;
}

interface ModelRun {
  id: string;
  model_artifact_id: string;
  status: 'pending' | 'running' | 'completed' | 'errored';
  metrics: Record<string, any> | null;
  started_at: string;
  updated_at: string;
}

interface Feedback {
  id: string;
  model_run_id: string;
  user_id: string;
  comment: string;
  rating: number;
  inserted_at: string;
}

interface CreateRunPayload {
  model_artifact_id: string;
}

interface CreateFeedbackPayload {
  model_run_id: string;
  comment: string;
  rating: number;
}

class CerebrosAPI {
  private baseUrl: string;
  private token: string | null = null;

  constructor(baseUrl: string = '/api') {
    this.baseUrl = baseUrl;
    // Try to get token from localStorage or Phoenix auth
    this.token = localStorage.getItem('auth_token');
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      ...(this.token && { Authorization: `Bearer ${this.token}` }),
      ...options.headers
    };

    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      ...options,
      headers
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: 'Request failed' }));
      throw new Error(error.message || `HTTP ${response.status}`);
    }

    return response.json();
  }

  // Model Artifacts
  async getModelArtifacts(): Promise<ModelArtifact[]> {
    return this.request<ModelArtifact[]>('/model_artifacts');
  }

  async getModelArtifact(id: string): Promise<ModelArtifact> {
    return this.request<ModelArtifact>(`/model_artifacts/${id}`);
  }

  // Model Runs
  async getModelRuns(filters?: Record<string, any>): Promise<ModelRun[]> {
    const params = new URLSearchParams(filters as any);
    return this.request<ModelRun[]>(`/model_runs?${params}`);
  }

  async getModelRun(id: string): Promise<ModelRun> {
    return this.request<ModelRun>(`/model_runs/${id}`);
  }

  async createModelRun(payload: CreateRunPayload): Promise<ModelRun> {
    return this.request<ModelRun>('/model_runs', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  }

  // Feedback
  async getFeedbackForRun(runId: string): Promise<Feedback[]> {
    return this.request<Feedback[]>(`/feedbacks?model_run_id=${runId}`);
  }

  async createFeedback(payload: CreateFeedbackPayload): Promise<Feedback> {
    return this.request<Feedback>('/feedbacks', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  }

  // WebSocket for real-time updates (optional)
  subscribeToRun(runId: string, onUpdate: (run: ModelRun) => void) {
    // Using Phoenix Channels for real-time updates
    // This would require Phoenix.Socket from phoenix npm package
    console.log(`Subscribing to run ${runId}`);
    // Implementation would connect to Phoenix Channel
  }

  setToken(token: string) {
    this.token = token;
    localStorage.setItem('auth_token', token);
  }

  clearToken() {
    this.token = null;
    localStorage.removeItem('auth_token');
  }
}

export const api = new CerebrosAPI();
export type { ModelArtifact, ModelRun, Feedback, CreateRunPayload, CreateFeedbackPayload };
