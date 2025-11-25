import React, { useState } from 'react';
import ModelEvaluation from './components/ModelEvaluation';
import VersionHistory from './components/VersionHistory';
import RunDetails from './components/RunDetails';
import './styles/cerebros.css';

type View = 'evaluation' | 'history' | 'details';

interface CerebrosAppState {
  currentView: View;
  selectedRunId: string | null;
}

const CerebrosApp: React.FC = () => {
  const [state, setState] = useState<CerebrosAppState>({
    currentView: 'evaluation',
    selectedRunId: null
  });

  const handleViewChange = (view: View) => {
    setState({ ...state, currentView: view });
  };

  const handleRunSelect = (runId: string) => {
    setState({ currentView: 'details', selectedRunId: runId });
  };

  return (
    <div className="cerebros-app">
      <header className="cerebros-header">
        <h1>Cerebros Model Evaluation System</h1>
        <nav className="cerebros-nav">
          <button 
            className={state.currentView === 'evaluation' ? 'active' : ''}
            onClick={() => handleViewChange('evaluation')}
          >
            New Evaluation
          </button>
          <button 
            className={state.currentView === 'history' ? 'active' : ''}
            onClick={() => handleViewChange('history')}
          >
            Version History
          </button>
        </nav>
      </header>

      <main className="cerebros-main">
        {state.currentView === 'evaluation' && (
          <ModelEvaluation onRunCreated={handleRunSelect} />
        )}
        {state.currentView === 'history' && (
          <VersionHistory onRunSelect={handleRunSelect} />
        )}
        {state.currentView === 'details' && state.selectedRunId && (
          <RunDetails 
            runId={state.selectedRunId} 
            onBack={() => handleViewChange('history')}
          />
        )}
      </main>
    </div>
  );
};

export default CerebrosApp;
