/**
 * Thunderfield - Animated Thunderbit visualization hook
 *
 * Renders Thunderbits as animated glyphs in a 2D field. Each bit spawns at center,
 * grows to target size, and drifts to its orbital position based on kind and age.
 *
 * Features:
 * - Smooth spawn/drift/fade animations
 * - Energy-based sizing and glow
 * - Kind-based coloring
 * - Relation lines between linked bits
 * - Hover tooltips
 * - Click to select
 */

export const Thunderfield = {
  mounted() {
    this.container = this.el.querySelector('[id$="-bits"]') || this.el
    this.bits = new Map()
    this.animationFrame = null
    this.selectedId = null

    // Parse initial data
    this.parseData()

    // Start animation loop
    this.startAnimation()

    // Set up event listeners
    this.setupEvents()
  },

  updated() {
    this.parseData()
  },

  destroyed() {
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame)
    }
  },

  parseData() {
    try {
      const bitsData = JSON.parse(this.el.dataset.bits || '[]')
      const showRelations = this.el.dataset.showRelations === 'true'
      this.selectedId = this.el.dataset.selected || null

      // Process new bits
      const currentIds = new Set(bitsData.map(b => b.id))

      // Add new bits
      bitsData.forEach(bitData => {
        if (!this.bits.has(bitData.id)) {
          this.spawnBit(bitData)
        } else {
          // Update existing bit
          const bit = this.bits.get(bitData.id)
          bit.data = bitData
          bit.targetEnergy = bitData.energy
        }
      })

      // Mark removed bits for fade-out
      this.bits.forEach((bit, id) => {
        if (!currentIds.has(id)) {
          bit.fading = true
        }
      })

      this.showRelations = showRelations

    } catch (e) {
      console.error('Thunderfield: Failed to parse bits data', e)
    }
  },

  spawnBit(bitData) {
    const bit = {
      id: bitData.id,
      data: bitData,
      // Animation state
      phase: 'spawning', // spawning -> active -> fading -> removed
      spawnProgress: 0,
      currentEnergy: 0,
      targetEnergy: bitData.energy,
      currentX: 0.5,
      currentY: 0.5,
      targetX: bitData.position?.x || 0.5,
      targetY: bitData.position?.y || 0.5,
      rotation: Math.random() * 360,
      fading: false,
      opacity: 0,
      // DOM element
      element: null
    }

    // Calculate target position based on kind and index
    this.calculateTargetPosition(bit)

    // Create DOM element
    bit.element = this.createBitElement(bit)
    this.container.appendChild(bit.element)

    this.bits.set(bitData.id, bit)
  },

  calculateTargetPosition(bit) {
    const kind = bit.data.kind
    const index = this.bits.size

    // Different kinds orbit at different radii
    const kindRadii = {
      question: 0.25,
      command: 0.30,
      goal: 0.35,
      intent: 0.20,
      memory: 0.40,
      assertion: 0.28,
      world_update: 0.33,
      error: 0.38,
      system: 0.42
    }

    const radius = kindRadii[kind] || 0.3
    const angle = (index * 137.5 * Math.PI / 180) + Math.random() * 0.5 // Golden angle + jitter

    bit.targetX = 0.5 + radius * Math.cos(angle)
    bit.targetY = 0.5 + radius * Math.sin(angle)
  },

  createBitElement(bit) {
    const el = document.createElement('div')
    el.className = 'thunderbit absolute transition-opacity cursor-pointer'
    el.dataset.bitId = bit.id
    el.style.willChange = 'transform, opacity'

    // Inner glyph
    const glyph = document.createElement('div')
    glyph.className = 'thunderbit-glyph'
    el.appendChild(glyph)

    // Tooltip
    const tooltip = document.createElement('div')
    tooltip.className = 'thunderbit-tooltip hidden absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 bg-slate-900/95 border border-cyan-500/30 rounded-lg text-xs text-white whitespace-nowrap z-50 pointer-events-none'
    tooltip.innerHTML = `
      <div class="font-medium">${bit.data.kind}</div>
      <div class="text-gray-400 max-w-48 truncate">${this.escapeHtml(bit.data.content)}</div>
      ${bit.data.tags?.length ? `<div class="text-cyan-400 mt-1">${bit.data.tags.slice(0, 3).join(', ')}</div>` : ''}
    `
    el.appendChild(tooltip)

    return el
  },

  escapeHtml(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  },

  setupEvents() {
    // Hover effects
    this.container.addEventListener('mouseenter', (e) => {
      const bitEl = e.target.closest('.thunderbit')
      if (bitEl) {
        const tooltip = bitEl.querySelector('.thunderbit-tooltip')
        if (tooltip) tooltip.classList.remove('hidden')
      }
    }, true)

    this.container.addEventListener('mouseleave', (e) => {
      const bitEl = e.target.closest('.thunderbit')
      if (bitEl) {
        const tooltip = bitEl.querySelector('.thunderbit-tooltip')
        if (tooltip) tooltip.classList.add('hidden')
      }
    }, true)

    // Click to select
    this.container.addEventListener('click', (e) => {
      const bitEl = e.target.closest('.thunderbit')
      if (bitEl) {
        const bitId = bitEl.dataset.bitId
        this.pushEvent('select_bit', { id: bitId })
      }
    })
  },

  startAnimation() {
    let lastTime = performance.now()

    const animate = (time) => {
      const dt = Math.min((time - lastTime) / 1000, 0.1) // Cap delta time
      lastTime = time

      this.updateBits(dt)
      this.renderBits()

      if (this.showRelations) {
        this.renderRelations()
      }

      this.animationFrame = requestAnimationFrame(animate)
    }

    this.animationFrame = requestAnimationFrame(animate)
  },

  updateBits(dt) {
    const bitsToRemove = []

    this.bits.forEach((bit, id) => {
      // Spawn animation
      if (bit.phase === 'spawning') {
        bit.spawnProgress += dt * 2 // 0.5s spawn time
        bit.opacity = Math.min(bit.spawnProgress, 1)
        bit.currentEnergy = bit.targetEnergy * Math.min(bit.spawnProgress, 1)

        if (bit.spawnProgress >= 1) {
          bit.phase = 'active'
        }
      }

      // Active - drift toward target
      if (bit.phase === 'active' || bit.phase === 'spawning') {
        const driftSpeed = 0.5
        bit.currentX += (bit.targetX - bit.currentX) * driftSpeed * dt
        bit.currentY += (bit.targetY - bit.currentY) * driftSpeed * dt
        bit.currentEnergy += (bit.targetEnergy - bit.currentEnergy) * 2 * dt
        bit.rotation += 10 * dt // Slow rotation
      }

      // Fading
      if (bit.fading) {
        bit.opacity -= dt * 2 // 0.5s fade
        if (bit.opacity <= 0) {
          bitsToRemove.push(id)
        }
      }
    })

    // Remove faded bits
    bitsToRemove.forEach(id => {
      const bit = this.bits.get(id)
      if (bit?.element) {
        bit.element.remove()
      }
      this.bits.delete(id)
    })
  },

  renderBits() {
    const rect = this.container.getBoundingClientRect()

    this.bits.forEach(bit => {
      if (!bit.element) return

      const x = bit.currentX * rect.width
      const y = bit.currentY * rect.height
      const size = 16 + bit.currentEnergy * 32
      const color = bit.data.ui?.color || '#60A5FA'

      bit.element.style.transform = `translate(${x - size / 2}px, ${y - size / 2}px)`
      bit.element.style.opacity = bit.opacity

      // Update glyph
      const glyph = bit.element.querySelector('.thunderbit-glyph')
      if (glyph) {
        glyph.style.width = `${size}px`
        glyph.style.height = `${size}px`
        glyph.style.background = this.getGlyphBackground(bit, color)
        glyph.style.borderRadius = this.getGlyphBorderRadius(bit.data.ui?.shape)
        glyph.style.boxShadow = `0 0 ${bit.currentEnergy * 20}px ${color}66`
        glyph.style.transform = `rotate(${bit.rotation}deg)`

        // Selected state
        if (bit.id === this.selectedId) {
          glyph.style.boxShadow = `0 0 ${bit.currentEnergy * 20}px ${color}66, 0 0 0 2px #22D3EE, 0 0 20px #22D3EE44`
        }
      }
    })
  },

  getGlyphBackground(bit, color) {
    const shape = bit.data.ui?.shape

    switch (shape) {
      case 'capsule':
        return `linear-gradient(90deg, ${color}66, ${color}AA, ${color}66)`
      case 'bubble':
        return `${color}44`
      default:
        return `radial-gradient(circle, ${color}AA, ${color}66)`
    }
  },

  getGlyphBorderRadius(shape) {
    switch (shape) {
      case 'hex':
        return '0'
      case 'diamond':
        return '0'
      case 'square':
        return '4px'
      case 'triangle':
        return '0'
      default:
        return '50%'
    }
  },

  renderRelations() {
    // Remove existing lines
    this.container.querySelectorAll('.relation-line').forEach(el => el.remove())

    const rect = this.container.getBoundingClientRect()

    this.bits.forEach(bit => {
      if (!bit.data.links?.length) return

      bit.data.links.forEach(linkId => {
        const linkedBit = this.bits.get(linkId)
        if (!linkedBit) return

        // Create SVG line
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
        svg.classList.add('relation-line')
        svg.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 0;'

        const line = document.createElementNS('http://www.w3.org/2000/svg', 'line')
        line.setAttribute('x1', bit.currentX * rect.width)
        line.setAttribute('y1', bit.currentY * rect.height)
        line.setAttribute('x2', linkedBit.currentX * rect.width)
        line.setAttribute('y2', linkedBit.currentY * rect.height)
        line.setAttribute('stroke', 'rgba(34, 211, 238, 0.2)')
        line.setAttribute('stroke-width', '1')
        line.setAttribute('stroke-dasharray', '4 4')

        svg.appendChild(line)
        this.container.insertBefore(svg, this.container.firstChild)
      })
    })
  }
}

export default Thunderfield
