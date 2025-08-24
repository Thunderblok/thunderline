// Thunderline Phoenix LiveView App with 3D CA Visualization

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import hooks
import { CAVisualization } from "./hooks/ca_visualization"

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
  AutoScroll,
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
