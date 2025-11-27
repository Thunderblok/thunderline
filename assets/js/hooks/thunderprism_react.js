/**
 * ThunderPrism React Hook
 * 
 * Bridges LiveView with React Three Fiber component.
 * Handles data flow and real-time updates.
 */

import React from 'react';
import { createRoot } from 'react-dom/client';
import ThunderPrismApp from '../thunderprism/App';

let root = null;

export const ThunderPrismReact = {
  mounted() {
    console.log('ThunderPrismReact hook mounted');
    
    // Initialize React app
    this.initReact();
    
    // Listen for graph updates from LiveView
    this.handleEvent("graph_updated", (data) => {
      console.log('Received graph_updated from LiveView:', data);
      this.updateData(data);
    });

    // Listen for selection clear events
    this.handleEvent("clear_selection", () => {
      window.dispatchEvent(new CustomEvent('thunderprism:clear-selection'));
    });

    // Listen for React ready signal
    window.addEventListener('thunderprism:react-ready', () => {
      console.log('React signaled ready, requesting initial data');
      this.pushEvent("refresh_graph", {});
    });

    // Request initial data from LiveView after a short delay for React to mount
    setTimeout(() => {
      console.log('Requesting initial graph data');
      this.pushEvent("refresh_graph", {});
    }, 100);
  },

  initReact() {
    console.log('Initializing React Three Fiber app');
    if (root) {
      root.unmount();
    }
    root = createRoot(this.el);
    root.render(React.createElement(ThunderPrismApp));
  },

  updateData(data) {
    console.log('Dispatching data to React:', data);
    // Pass data to React component via custom event
    window.dispatchEvent(new CustomEvent('thunderprism:data-update', {
      detail: data
    }));

    // Update LiveView stats
    this.pushEvent("graph_loaded", {
      node_count: data.nodes?.length || 0,
      link_count: data.links?.length || 0
    });
  },

  updated() {
    // Handle LiveView attribute changes
    const pacId = this.el.dataset.pacId;
    const limit = parseInt(this.el.dataset.limit) || 100;

    console.log('Hook updated, config:', { pacId, limit });
    window.dispatchEvent(new CustomEvent('thunderprism:config-changed', {
      detail: { pacFilter: pacId || null, limit }
    }));
  },

  destroyed() {
    console.log('ThunderPrismReact hook destroyed');
    if (root) {
      root.unmount();
      root = null;
    }
  }
};
