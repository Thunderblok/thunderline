/**
 * EventFlow Canvas Hook - Real-time ThunderFlow Event Visualization
 * 
 * Renders stacked area chart showing event pipeline distribution over time.
 * Reuses Canvas patterns from MetricsChart for consistency.
 */

export const EventFlow = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext('2d')
    this.parseData()
    this.drawChart()
  },

  updated() {
    this.parseData()
    this.drawChart()
  },

  parseData() {
    try {
      const dataAttr = this.el.dataset.flowData
      const configAttr = this.el.dataset.chartConfig
      
      this.flowData = dataAttr ? JSON.parse(dataAttr) : []
      this.config = configAttr ? JSON.parse(configAttr) : {}
    } catch (e) {
      console.error('Failed to parse EventFlow data:', e)
      this.flowData = []
      this.config = {}
    }
  },

  drawChart() {
    if (!this.ctx || !this.flowData || this.flowData.length === 0) return

    const { width, height } = this.canvas
    const padding = { top: 40, right: 40, bottom: 60, left: 70 }
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom

    // Clear canvas
    this.ctx.clearRect(0, 0, width, height)

    // Draw background
    this.ctx.fillStyle = '#0f172a'
    this.ctx.fillRect(0, 0, width, height)

    // Calculate scales
    const windows = this.flowData.map(d => d.window)
    const maxWindow = Math.max(...windows)
    const minWindow = Math.min(...windows)
    
    // Find max total events across all windows
    const maxTotal = Math.max(
      ...this.flowData.map(d => (d.realtime || 0) + (d.cross_domain || 0) + (d.general || 0))
    )

    const xScale = (window) => {
      const normalizedWindow = (window - minWindow) / (maxWindow - minWindow || 1)
      return padding.left + normalizedWindow * chartWidth
    }

    const yScale = (value) => {
      return height - padding.bottom - (value / (maxTotal || 1)) * chartHeight
    }

    // Draw grid
    this.drawGrid(padding, chartWidth, chartHeight, maxTotal)

    // Draw stacked areas (bottom to top: general, cross_domain, realtime)
    this.drawStackedArea(xScale, yScale, padding)

    // Draw axes
    this.drawAxes(padding, chartWidth, chartHeight, minWindow, maxWindow, maxTotal)

    // Draw legend
    this.drawLegend(padding)
  },

  drawGrid(padding, chartWidth, chartHeight, maxTotal) {
    this.ctx.strokeStyle = '#1e293b'
    this.ctx.lineWidth = 1

    // Horizontal grid lines
    const ySteps = 5
    for (let i = 0; i <= ySteps; i++) {
      const y = padding.top + (chartHeight / ySteps) * i
      this.ctx.beginPath()
      this.ctx.moveTo(padding.left, y)
      this.ctx.lineTo(padding.left + chartWidth, y)
      this.ctx.stroke()
    }

    // Vertical grid lines
    const xSteps = Math.min(this.flowData.length, 10)
    for (let i = 0; i <= xSteps; i++) {
      const x = padding.left + (chartWidth / xSteps) * i
      this.ctx.beginPath()
      this.ctx.moveTo(x, padding.top)
      this.ctx.lineTo(x, padding.top + chartHeight)
      this.ctx.stroke()
    }
  },

  drawStackedArea(xScale, yScale, padding) {
    const colors = this.config.colors || {
      general: '#10b981',
      cross_domain: '#8b5cf6',
      realtime: '#3b82f6'
    }

    // Draw general area (bottom layer)
    this.drawArea(xScale, yScale, 'general', colors.general, 0)

    // Draw cross_domain area (middle layer)
    this.drawArea(xScale, yScale, 'cross_domain', colors.cross_domain, 'general')

    // Draw realtime area (top layer)
    this.drawArea(xScale, yScale, 'realtime', colors.realtime, ['general', 'cross_domain'])
  },

  drawArea(xScale, yScale, pipeline, color, basePipelines) {
    if (!this.flowData || this.flowData.length === 0) return

    const { width, height } = this.canvas
    const padding = { top: 40, right: 40, bottom: 60, left: 70 }
    
    this.ctx.fillStyle = color + '40' // Add transparency
    this.ctx.strokeStyle = color
    this.ctx.lineWidth = 2

    this.ctx.beginPath()

    // Calculate base values (sum of previous pipelines)
    const getBaseValue = (data) => {
      if (!basePipelines) return 0
      const pipelines = Array.isArray(basePipelines) ? basePipelines : [basePipelines]
      return pipelines.reduce((sum, p) => sum + (data[p] || 0), 0)
    }

    // Draw top line (left to right)
    this.flowData.forEach((data, i) => {
      const x = xScale(data.window)
      const baseValue = getBaseValue(data)
      const topValue = baseValue + (data[pipeline] || 0)
      const y = yScale(topValue)

      if (i === 0) {
        this.ctx.moveTo(x, y)
      } else {
        this.ctx.lineTo(x, y)
      }
    })

    // Draw bottom line (right to left)
    for (let i = this.flowData.length - 1; i >= 0; i--) {
      const data = this.flowData[i]
      const x = xScale(data.window)
      const baseValue = getBaseValue(data)
      const y = yScale(baseValue)
      this.ctx.lineTo(x, y)
    }

    this.ctx.closePath()
    this.ctx.fill()
    this.ctx.stroke()
  },

  drawAxes(padding, chartWidth, chartHeight, minWindow, maxWindow, maxTotal) {
    const { width, height } = this.canvas
    
    this.ctx.strokeStyle = '#475569'
    this.ctx.lineWidth = 2
    this.ctx.fillStyle = '#cbd5e1'
    this.ctx.font = '12px monospace'

    // Y-axis
    this.ctx.beginPath()
    this.ctx.moveTo(padding.left, padding.top)
    this.ctx.lineTo(padding.left, height - padding.bottom)
    this.ctx.stroke()

    // X-axis
    this.ctx.beginPath()
    this.ctx.moveTo(padding.left, height - padding.bottom)
    this.ctx.lineTo(width - padding.right, height - padding.bottom)
    this.ctx.stroke()

    // Y-axis labels
    const ySteps = 5
    for (let i = 0; i <= ySteps; i++) {
      const value = Math.round((maxTotal / ySteps) * (ySteps - i))
      const y = padding.top + (chartHeight / ySteps) * i
      this.ctx.textAlign = 'right'
      this.ctx.textBaseline = 'middle'
      this.ctx.fillText(value.toString(), padding.left - 10, y)
    }

    // X-axis labels (show time windows)
    const xSteps = Math.min(this.flowData.length, 10)
    const step = Math.floor(this.flowData.length / xSteps) || 1
    
    for (let i = 0; i < this.flowData.length; i += step) {
      const data = this.flowData[i]
      const x = xScale(data.window)
      const label = `${data.window}s`
      
      this.ctx.save()
      this.ctx.translate(x, height - padding.bottom + 20)
      this.ctx.rotate(-Math.PI / 4)
      this.ctx.textAlign = 'right'
      this.ctx.textBaseline = 'middle'
      this.ctx.fillText(label, 0, 0)
      this.ctx.restore()
    }

    // Axis titles
    this.ctx.fillStyle = '#94a3b8'
    this.ctx.font = '14px sans-serif'
    
    // Y-axis title
    this.ctx.save()
    this.ctx.translate(15, height / 2)
    this.ctx.rotate(-Math.PI / 2)
    this.ctx.textAlign = 'center'
    this.ctx.fillText(this.config.y_label || 'Events', 0, 0)
    this.ctx.restore()

    // X-axis title
    this.ctx.textAlign = 'center'
    this.ctx.fillText(this.config.x_label || 'Time Window (seconds ago)', width / 2, height - 10)
  },

  drawLegend(padding) {
    const colors = this.config.colors || {
      realtime: '#3b82f6',
      cross_domain: '#8b5cf6',
      general: '#10b981'
    }

    const labels = {
      realtime: 'Real-Time',
      cross_domain: 'Cross-Domain',
      general: 'General'
    }

    const legendX = padding.left + 20
    const legendY = padding.top + 10
    const boxSize = 12
    const spacing = 20

    this.ctx.font = '12px sans-serif'
    this.ctx.textBaseline = 'middle'

    let offsetX = 0

    Object.entries(colors).forEach(([key, color]) => {
      // Draw color box
      this.ctx.fillStyle = color
      this.ctx.fillRect(legendX + offsetX, legendY - boxSize / 2, boxSize, boxSize)

      // Draw label
      this.ctx.fillStyle = '#cbd5e1'
      this.ctx.textAlign = 'left'
      this.ctx.fillText(labels[key] || key, legendX + offsetX + boxSize + 5, legendY)

      // Calculate offset for next item
      const textWidth = this.ctx.measureText(labels[key] || key).width
      offsetX += boxSize + textWidth + spacing
    })
  }
}
