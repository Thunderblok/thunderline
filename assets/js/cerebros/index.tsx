import React from 'react';
import { createRoot } from 'react-dom/client';
import CerebrosApp from './App';

// Mount React app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('cerebros-root');
  if (container) {
    const root = createRoot(container);
    root.render(<CerebrosApp />);
  }
});
