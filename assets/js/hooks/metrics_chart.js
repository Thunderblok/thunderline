/**
 * MetricsChart Hook
 * 
 * Real-time ML metrics visualization using Canvas API.
 * Reuses patterns from Whiteboard hook for smooth rendering.
 * 
 * Features:
 * - Multi-trial metric plotting (loss, accuracy, etc.)
 * - Real-time updates via Phoenix events
 * - Color-coded trial curves
 * - Smooth canvas rendering
 * - Automatic scaling and axis labels
 */

export const MetricsChart = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext('2d')
    this.metric = this.el.dataset.metric
    this.trials = JSON.parse(this.el.dataset.trials || '{}')
    
    // Chart styling
    this.colors = [
      '#8b5cf6', // purple
      '#06b6d4', // cyan
      '#f59e0b', // amber
      '#10b981', // emerald
      '#ef4444', // red
      '#ec4899', // pink
    ]
    
    this.padding = { top: 20, right: 20, bottom: 40, left: 60 }
    
    // Initial render
    this.renderChart()
    
    // Listen for real-time metric updates
    this.handleEvent('update_metrics', (payload) => {
      if (this.trials[payload.trial_id]) {
        this.trials[payload.trial_id] = payload.metrics
        this.renderChart()
      }
    })
  },
  
  updated() {
    // Re-parse trials data when component updates
    const newTrials = JSON.parse(this.el.dataset.trials || '{}')
    
    // Only re-render if data actually changed
    if (JSON.stringify(newTrials) !== JSON.stringify(this.trials)) {
      this.trials = newTrials
      this.renderChart()
    }
  },
  
  renderChart() {
    const { width, height } = this.canvas
    const { ctx, padding } = this
    
    // Clear canvas
    ctx.clearRect(0, 0, width, height)
    
    // Extract all metric series for this metric type
    const allSeries = Object.entries(this.trials)
      .map(([trialId, trialData]) => ({
        trialId,
        data: trialData[this.metric] || [],
        label: trialData.trial_id,
        spectralNorm: trialData.spectral_norm
      }))
      .filter(s => s.data.length > 0)
    
    if (allSeries.length === 0) {
      this.drawEmptyState()
      return
    }
    
    // Calculate bounds
    const bounds = this.calculateBounds(allSeries)
    
    // Draw axes and grid
    this.drawAxes(bounds)
    this.drawGrid(bounds)
    
    // Draw each trial's metric curve
    allSeries.forEach((series, idx) => {
      const color = this.colors[idx % this.colors.length]
      this.drawCurve(series.data, color, bounds, series.spectralNorm)
    })
    
    // Draw legend
    this.drawLegend(allSeries)
  },
  
  calculateBounds(allSeries) {
    let minX = Infinity, maxX = -Infinity
    let minY = Infinity, maxY = -Infinity
    
    allSeries.forEach(series => {
      series.data.forEach(([x, y]) => {
        minX = Math.min(minX, x)
        maxX = Math.max(maxX, x)
        minY = Math.min(minY, y)
        maxY = Math.max(maxY, y)
      })
    })
    
    // Add 10% padding to Y axis
    const yRange = maxY - minY
    minY -= yRange * 0.1
    maxY += yRange * 0.1
    
    return { minX, maxX, minY, maxY }
  },
  
  drawAxes(bounds) {
    const { ctx, canvas, padding } = this
    const { width, height } = canvas
    
    ctx.strokeStyle = '#475569' // slate-600
    ctx.lineWidth = 1
    
    // Y axis
    ctx.beginPath()
    ctx.moveTo(padding.left, padding.top)
    ctx.lineTo(padding.left, height - padding.bottom)
    ctx.stroke()
    
    // X axis
    ctx.beginPath()
    ctx.moveTo(padding.left, height - padding.bottom)
    ctx.lineTo(width - padding.right, height - padding.bottom)
    ctx.stroke()
    
    // Y axis labels
    ctx.fillStyle = '#94a3b8' // slate-400
    ctx.font = '11px monospace'
    ctx.textAlign = 'right'
    
    const ySteps = 5
    for (let i = 0; i <= ySteps; i++) {
      const y = padding.top + ((height - padding.top - padding.bottom) / ySteps) * i
      const value = bounds.maxY - ((bounds.maxY - bounds.minY) / ySteps) * i
      
      ctx.fillText(value.toFixed(3), padding.left - 10, y + 4)
    }
    
    // X axis label
    ctx.textAlign = 'center'
    ctx.fillText('Step', width / 2, height - 10)
    
    // Y axis label (rotated)
    ctx.save()
    ctx.translate(15, height / 2)
    ctx.rotate(-Math.PI / 2)
    ctx.textAlign = 'center'
    ctx.fillText(this.metric.charAt(0).toUpperCase() + this.metric.slice(1), 0, 0)
    ctx.restore()
  },
  
  drawGrid(bounds) {
    const { ctx, canvas, padding } = this
    const { width, height } = canvas
    
    ctx.strokeStyle = '#1e293b' // slate-800
    ctx.lineWidth = 1
    ctx.setLineDash([2, 4])
    
    // Horizontal grid lines
    const ySteps = 5
    for (let i = 1; i < ySteps; i++) {
      const y = padding.top + ((height - padding.top - padding.bottom) / ySteps) * i
      
      ctx.beginPath()
      ctx.moveTo(padding.left, y)
      ctx.lineTo(width - padding.right, y)
      ctx.stroke()
    }
    
    ctx.setLineDash([])
  },
  
  drawCurve(data, color, bounds, spectralNorm) {
    const { ctx, canvas, padding } = this
    const { width, height } = canvas
    
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom
    
    // Transform data points to canvas coordinates
    const points = data.map(([x, y]) => ({
      x: padding.left + ((x - bounds.minX) / (bounds.maxX - bounds.minX)) * chartWidth,
      y: padding.top + chartHeight - ((y - bounds.minY) / (bounds.maxY - bounds.minY)) * chartHeight
    }))
    
    if (points.length === 0) return
    
    // Draw line
    ctx.strokeStyle = color
    ctx.lineWidth = spectralNorm ? 2.5 : 2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    
    if (spectralNorm) {
      // Dashed line for spectral norm trials
      ctx.setLineDash([5, 3])
    }
    
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y)
    }
    
    ctx.stroke()
    ctx.setLineDash([])
    
    // Draw points
    ctx.fillStyle = color
    points.forEach(point => {
      ctx.beginPath()
      ctx.arc(point.x, point.y, 3, 0, 2 * Math.PI)
      ctx.fill()
    })
  },
  
  drawLegend(allSeries) {
    const { ctx, canvas, padding } = this
    const { width } = canvas
    
    const legendX = width - padding.right - 150
    const legendY = padding.top + 10
    const lineHeight = 20
    
    ctx.font = '11px sans-serif'
    ctx.textAlign = 'left'
    
    allSeries.forEach((series, idx) => {
      const color = this.colors[idx % this.colors.length]
      const y = legendY + idx * lineHeight
      
      // Color swatch
      ctx.fillStyle = color
      ctx.fillRect(legendX, y - 8, 12, 12)
      
      // Trial label (truncated)
      ctx.fillStyle = '#e2e8f0' // slate-200
      const label = series.label.substring(0, 12) + (series.label.length > 12 ? '...' : '')
      ctx.fillText(label, legendX + 18, y + 2)
      
      // Spectral norm indicator
      if (series.spectralNorm) {
        ctx.fillStyle = '#a78bfa' // purple-400
        ctx.fillText('SN', legendX + 120, y + 2)
      }
    })
  },
  
  drawEmptyState() {
    const { ctx, canvas } = this
    const { width, height } = canvas
    
    ctx.fillStyle = '#64748b' // slate-500
    ctx.font = '14px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText('No metrics data available', width / 2, height / 2)
    
    ctx.font = '12px sans-serif'
    ctx.fillStyle = '#94a3b8' // slate-400
    ctx.fillText('Metrics will appear here once trials start reporting', width / 2, height / 2 + 24)
  }
}
