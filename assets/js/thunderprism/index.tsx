import React from 'react';
import { createRoot } from 'react-dom/client';
import ThunderPrismApp from './App';

// Mount React app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('thunderprism-root');
  if (container) {
    const root = createRoot(container);
    root.render(<ThunderPrismApp />);
  }
});

// Also handle LiveView updates - mount when the container appears
const observer = new MutationObserver((mutations) => {
  mutations.forEach((mutation) => {
    mutation.addedNodes.forEach((node) => {
      if (node instanceof HTMLElement) {
        const container = node.querySelector?.('#thunderprism-root') || 
                         (node.id === 'thunderprism-root' ? node : null);
        if (container && !container.hasAttribute('data-react-mounted')) {
          container.setAttribute('data-react-mounted', 'true');
          const root = createRoot(container);
          root.render(<ThunderPrismApp />);
        }
      }
    });
  });
});

observer.observe(document.body, { childList: true, subtree: true });
