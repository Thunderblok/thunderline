// Thunderline Phoenix LiveView App with 3D CA Visualization

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import hooks
import { CAVisualization } from "./hooks/ca_visualization"
import { Whiteboard } from "./hooks/whiteboard"
import { MetricsChart } from "./hooks/metrics_chart"
import { EventFlow } from "./hooks/event_flow"
import { ThunderPrismGraph } from "./hooks/thunderprism_graph"
import { ThunderPrismReact } from "./hooks/thunderprism_react"

// Simple auto-scroll hook for chat & event flow streams
// TODO: Enhance with user scroll lock (pause autoscroll while user hovering / scrolled up)
const AutoScroll = {
  mounted() { this.scrollToBottom() },
  updated() { this.scrollToBottom() },
  scrollToBottom() {
    try { this.el.scrollTop = this.el.scrollHeight } catch (_) { }
  }
}

// Socket and LiveView setup
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Configure hooks
let Hooks = {
  CAVisualization,
  Whiteboard,
  MetricsChart,
  EventFlow,
  ThunderPrismGraph,
  ThunderPrismReact,
  AutoScroll,
  Tabs: {
    mounted() {
      // Persist and a11y keyboard navigation for tabs
      const container = this.el
      const links = Array.from(container.querySelectorAll('[role="tab"]'))
      const storageKey = this.getStorageKey()
      // Restore last tab if no ?tab present
      const url = new URL(window.location.href)
      const hasTab = url.searchParams.has('tab')
      const saved = localStorage.getItem(storageKey)
      if (!hasTab && saved) {
        // Trigger a patch navigation by clicking the matching tab link
        const match = links.find(l => l.dataset.tabKey === saved)
        if (match) match.click()
      }

      // Save on click
      links.forEach(link => {
        link.addEventListener('click', () => {
          const key = link.dataset.tabKey
          if (key) localStorage.setItem(storageKey, key)
        })
      })

      // Keyboard nav
      container.addEventListener('keydown', (e) => {
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return
        e.preventDefault()
        const currentIndex = links.findIndex(l => l.getAttribute('aria-selected') === 'true')
        let nextIndex = currentIndex
        if (e.key === 'ArrowRight') nextIndex = (currentIndex + 1) % links.length
        if (e.key === 'ArrowLeft') nextIndex = (currentIndex - 1 + links.length) % links.length
        if (e.key === 'Home') nextIndex = 0
        if (e.key === 'End') nextIndex = links.length - 1
        const next = links[nextIndex]
        if (next) {
          next.focus()
          next.click()
        }
      })
    },
    getStorageKey() {
      try {
        // Namespace by path so different dashboard routes keep independent selection
        const path = window.location.pathname
        return `thunderline:dashboard:last_tab:${path}`
      } catch (_) { return 'thunderline:dashboard:last_tab' }
    }
  },
  EventFlowScroll: {
    mounted() {
      this.userLocked = false
      this.handleScroll = () => {
        // If user scrolls up (not at bottom) lock autoscroll
        const threshold = 10
        const atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < threshold
        this.userLocked = !atBottom
      }
      this.el.addEventListener('scroll', this.handleScroll)
      this.scrollToBottom()
    },
    updated() {
      if (!this.userLocked) this.scrollToBottom()
    },
    destroyed() { this.el.removeEventListener('scroll', this.handleScroll) },
    scrollToBottom() { try { this.el.scrollTop = this.el.scrollHeight } catch (_) { } }
  }
}

// LiveSocket with hooks
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// Connect LiveSocket
liveSocket.connect()

// Expose liveSocket on window for debugging in dev
window.liveSocket = liveSocket

// Custom Thunderline Dashboard Events
window.addEventListener("phx:ca-data-update", (e) => {
  // Global CA data update handler
  console.log("CA data updated:", e.detail)
})

window.addEventListener("phx:connection-status", (e) => {
  // Connection status change handler
  const status = e.detail.connected ? "connected" : "disconnected"
  console.log("Connection status:", status)

  // Update UI indicators
  const indicators = document.querySelectorAll('.connection-indicator')
  indicators.forEach(indicator => {
    indicator.classList.toggle('connected', e.detail.connected)
    indicator.classList.toggle('disconnected', !e.detail.connected)
  })
})

// Dashboard specific functionality
document.addEventListener('DOMContentLoaded', function () {
  // Initialize dashboard-specific features
  initializeDashboardFeatures()
})

function initializeDashboardFeatures() {
  // Add glassmorphism hover effects
  const panels = document.querySelectorAll('.dashboard-panel')
  panels.forEach(panel => {
    panel.addEventListener('mouseenter', function () {
      this.style.backdropFilter = 'blur(20px)'
      this.style.transform = 'translateY(-2px)'
    })

    panel.addEventListener('mouseleave', function () {
      this.style.backdropFilter = 'blur(15px)'
      this.style.transform = 'translateY(0)'
    })
  })

  // Add smooth transitions for metrics
  const metrics = document.querySelectorAll('.metric-value')
  metrics.forEach(metric => {
    const observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (mutation) {
        if (mutation.type === 'childList' || mutation.type === 'characterData') {
          metric.style.animation = 'pulse 0.3s ease-in-out'
          setTimeout(() => {
            metric.style.animation = ''
          }, 300)
        }
      })
    })

    observer.observe(metric, {
      childList: true,
      subtree: true,
      characterData: true
    })
  })
}

// Add CSS animations dynamically
const style = document.createElement('style')
style.textContent = `
  @keyframes pulse {
    0% { transform: scale(1); }
    50% { transform: scale(1.05); }
    100% { transform: scale(1); }
  }
  
  .connection-indicator {
    transition: all 0.3s ease;
  }
  
  .connection-indicator.connected {
    color: #10b981;
    text-shadow: 0 0 5px #10b981;
  }
  
  .connection-indicator.disconnected {
    color: #ef4444;
    text-shadow: 0 0 5px #ef4444;
  }
  
  .dashboard-panel {
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }
  
  .metric-value {
    transition: all 0.3s ease;
  }
`
document.head.appendChild(style)
