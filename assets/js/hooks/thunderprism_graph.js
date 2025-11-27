/**
 * ThunderPrism 3D Force-Directed Graph Visualization
 * 
 * Uses Three.js to render ML decision DAG nodes from the ThunderPrism API.
 * Supports node selection, inspection, and real-time updates.
 */

import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'

export const ThunderPrismGraph = {
  mounted() {
    this.nodes = []
    this.links = []
    this.nodeObjects = new Map()
    this.linkObjects = []
    this.selectedNode = null
    this.hoveredNode = null

    // Initialize Three.js scene
    this.initScene()
    this.initLights()
    this.initControls()
    this.initRaycaster()

    // Load initial data
    this.loadGraphData()

    // Start animation loop
    this.animate()

    // Handle window resize
    this.handleResize = () => this.onResize()
    window.addEventListener('resize', this.handleResize)

    // Handle LiveView events
    this.handleEvent("graph_updated", (data) => {
      this.updateGraph(data)
    })

    this.handleEvent("select_node", ({ id }) => {
      this.selectNodeById(id)
    })

    this.handleEvent("clear_selection", () => {
      this.clearSelection()
    })
  },

  destroyed() {
    window.removeEventListener('resize', this.handleResize)
    if (this.animationId) {
      cancelAnimationFrame(this.animationId)
    }
    if (this.renderer) {
      this.renderer.dispose()
    }
  },

  initScene() {
    const container = this.el
    const width = container.clientWidth
    const height = container.clientHeight || 500

    // Scene
    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(0x0a0a0f)
    this.scene.fog = new THREE.FogExp2(0x0a0a0f, 0.002)

    // Camera
    this.camera = new THREE.PerspectiveCamera(60, width / height, 0.1, 2000)
    this.camera.position.set(0, 100, 200)

    // Renderer
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
    this.renderer.setSize(width, height)
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    container.appendChild(this.renderer.domElement)

    // Add grid helper
    const gridHelper = new THREE.GridHelper(400, 40, 0x1a1a2e, 0x1a1a2e)
    gridHelper.position.y = -50
    this.scene.add(gridHelper)

    // Add ambient particles for atmosphere
    this.addParticles()
  },

  initLights() {
    // Ambient light
    const ambient = new THREE.AmbientLight(0x404050, 0.5)
    this.scene.add(ambient)

    // Main directional light
    const directional = new THREE.DirectionalLight(0xffffff, 0.8)
    directional.position.set(50, 100, 50)
    this.scene.add(directional)

    // Point lights for glow effects
    const pointLight1 = new THREE.PointLight(0x22d3ee, 1, 200)
    pointLight1.position.set(50, 50, 50)
    this.scene.add(pointLight1)

    const pointLight2 = new THREE.PointLight(0x10b981, 0.8, 200)
    pointLight2.position.set(-50, -50, -50)
    this.scene.add(pointLight2)
  },

  initControls() {
    this.controls = new OrbitControls(this.camera, this.renderer.domElement)
    this.controls.enableDamping = true
    this.controls.dampingFactor = 0.05
    this.controls.enableZoom = true
    this.controls.minDistance = 50
    this.controls.maxDistance = 500
    this.controls.autoRotate = true
    this.controls.autoRotateSpeed = 0.5
  },

  initRaycaster() {
    this.raycaster = new THREE.Raycaster()
    this.mouse = new THREE.Vector2()

    this.renderer.domElement.addEventListener('mousemove', (e) => this.onMouseMove(e))
    this.renderer.domElement.addEventListener('click', (e) => this.onClick(e))
  },

  addParticles() {
    const geometry = new THREE.BufferGeometry()
    const count = 500
    const positions = new Float32Array(count * 3)

    for (let i = 0; i < count * 3; i++) {
      positions[i] = (Math.random() - 0.5) * 600
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3))

    const material = new THREE.PointsMaterial({
      size: 1.5,
      color: 0x22d3ee,
      transparent: true,
      opacity: 0.3,
      blending: THREE.AdditiveBlending
    })

    this.particles = new THREE.Points(geometry, material)
    this.scene.add(this.particles)
  },

  async loadGraphData() {
    try {
      const pacId = this.el.dataset.pacId || ''
      const limit = this.el.dataset.limit || '100'
      let url = `/api/thunderprism/graph?limit=${limit}`
      if (pacId) url += `&pac_id=${pacId}`

      const response = await fetch(url)
      const data = await response.json()

      this.updateGraph(data)
    } catch (error) {
      console.error('Failed to load ThunderPrism graph:', error)
      // Show empty state
      this.showEmptyState()
    }
  },

  updateGraph(data) {
    // Clear existing objects
    this.nodeObjects.forEach(obj => this.scene.remove(obj))
    this.linkObjects.forEach(obj => this.scene.remove(obj))
    this.nodeObjects.clear()
    this.linkObjects = []

    this.nodes = data.nodes || []
    this.links = data.links || []

    if (this.nodes.length === 0) {
      this.showEmptyState()
      return
    }

    // Position nodes using force-directed layout simulation
    this.positionNodes()

    // Create node meshes
    this.nodes.forEach(node => {
      const mesh = this.createNodeMesh(node)
      this.nodeObjects.set(node.id, mesh)
      this.scene.add(mesh)
    })

    // Create link lines
    this.links.forEach(link => {
      const line = this.createLinkLine(link)
      if (line) {
        this.linkObjects.push(line)
        this.scene.add(line)
      }
    })

    // Notify LiveView of node count
    this.pushEvent("graph_loaded", {
      node_count: this.nodes.length,
      link_count: this.links.length
    })
  },

  positionNodes() {
    // Simple force-directed layout
    const nodeCount = this.nodes.length

    // Arrange in a spiral pattern with some randomness
    this.nodes.forEach((node, index) => {
      const angle = (index / nodeCount) * Math.PI * 6
      const radius = 30 + (index / nodeCount) * 100
      const height = (node.iteration || index) * 5 - (nodeCount * 2.5)

      node.x = Math.cos(angle) * radius + (Math.random() - 0.5) * 20
      node.y = height + (Math.random() - 0.5) * 10
      node.z = Math.sin(angle) * radius + (Math.random() - 0.5) * 20
    })

    // Run simple force simulation
    for (let i = 0; i < 50; i++) {
      this.simulateForces()
    }
  },

  simulateForces() {
    const repulsion = 500
    const linkStrength = 0.1

    // Repulsion between nodes
    for (let i = 0; i < this.nodes.length; i++) {
      for (let j = i + 1; j < this.nodes.length; j++) {
        const a = this.nodes[i]
        const b = this.nodes[j]
        const dx = b.x - a.x
        const dy = b.y - a.y
        const dz = b.z - a.z
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1
        const force = repulsion / (dist * dist)

        const fx = (dx / dist) * force
        const fy = (dy / dist) * force
        const fz = (dz / dist) * force

        a.x -= fx
        a.y -= fy
        a.z -= fz
        b.x += fx
        b.y += fy
        b.z += fz
      }
    }

    // Attraction along links
    const nodeMap = new Map(this.nodes.map(n => [n.id, n]))
    this.links.forEach(link => {
      const source = nodeMap.get(link.source)
      const target = nodeMap.get(link.target)
      if (!source || !target) return

      const dx = target.x - source.x
      const dy = target.y - source.y
      const dz = target.z - source.z

      source.x += dx * linkStrength
      source.y += dy * linkStrength
      source.z += dz * linkStrength
      target.x -= dx * linkStrength
      target.y -= dy * linkStrength
      target.z -= dz * linkStrength
    })
  },

  createNodeMesh(node) {
    // Node size based on iteration or default
    const size = 3 + (node.iteration % 5)

    // Color based on chosen model
    const colorMap = {
      'model_a': 0x22d3ee, // cyan
      'model_b': 0x10b981, // emerald
      'model_c': 0xf59e0b, // amber
      'model_d': 0x8b5cf6, // violet
    }
    const color = colorMap[node.chosen_model] || 0x22d3ee

    // Create sphere geometry
    const geometry = new THREE.SphereGeometry(size, 16, 16)
    const material = new THREE.MeshPhongMaterial({
      color: color,
      emissive: color,
      emissiveIntensity: 0.3,
      transparent: true,
      opacity: 0.9
    })

    const mesh = new THREE.Mesh(geometry, material)
    mesh.position.set(node.x, node.y, node.z)
    mesh.userData = { node }

    // Add glow effect
    const glowGeometry = new THREE.SphereGeometry(size * 1.5, 16, 16)
    const glowMaterial = new THREE.MeshBasicMaterial({
      color: color,
      transparent: true,
      opacity: 0.15,
      blending: THREE.AdditiveBlending
    })
    const glow = new THREE.Mesh(glowGeometry, glowMaterial)
    mesh.add(glow)

    return mesh
  },

  createLinkLine(link) {
    const sourceNode = this.nodes.find(n => n.id === link.source)
    const targetNode = this.nodes.find(n => n.id === link.target)

    if (!sourceNode || !targetNode) return null

    const points = [
      new THREE.Vector3(sourceNode.x, sourceNode.y, sourceNode.z),
      new THREE.Vector3(targetNode.x, targetNode.y, targetNode.z)
    ]

    const geometry = new THREE.BufferGeometry().setFromPoints(points)

    // Color based on relation type
    const color = link.relation_type === 'next' ? 0x22d3ee : 0x8b5cf6

    const material = new THREE.LineBasicMaterial({
      color: color,
      transparent: true,
      opacity: 0.4,
      linewidth: 1
    })

    const line = new THREE.Line(geometry, material)
    line.userData = { link }

    return line
  },

  showEmptyState() {
    // Create floating text or indicator for empty state
    console.log('ThunderPrism: No nodes to display')
  },

  onMouseMove(event) {
    const rect = this.renderer.domElement.getBoundingClientRect()
    this.mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1

    // Check for intersections
    this.raycaster.setFromCamera(this.mouse, this.camera)
    const meshes = Array.from(this.nodeObjects.values())
    const intersects = this.raycaster.intersectObjects(meshes)

    // Reset previous hover
    if (this.hoveredNode && this.hoveredNode !== this.selectedNode) {
      const mesh = this.nodeObjects.get(this.hoveredNode.id)
      if (mesh) {
        mesh.scale.set(1, 1, 1)
        mesh.material.emissiveIntensity = 0.3
      }
    }

    if (intersects.length > 0) {
      const node = intersects[0].object.userData.node
      this.hoveredNode = node

      // Highlight hovered node
      const mesh = this.nodeObjects.get(node.id)
      if (mesh && node !== this.selectedNode) {
        mesh.scale.set(1.2, 1.2, 1.2)
        mesh.material.emissiveIntensity = 0.5
      }

      this.renderer.domElement.style.cursor = 'pointer'
      this.controls.autoRotate = false
    } else {
      this.hoveredNode = null
      this.renderer.domElement.style.cursor = 'default'
      this.controls.autoRotate = true
    }
  },

  onClick(event) {
    if (this.hoveredNode) {
      this.selectNode(this.hoveredNode)
    } else {
      this.clearSelection()
    }
  },

  selectNode(node) {
    // Deselect previous
    if (this.selectedNode) {
      const prevMesh = this.nodeObjects.get(this.selectedNode.id)
      if (prevMesh) {
        prevMesh.scale.set(1, 1, 1)
        prevMesh.material.emissiveIntensity = 0.3
      }
    }

    this.selectedNode = node

    // Highlight selected node
    const mesh = this.nodeObjects.get(node.id)
    if (mesh) {
      mesh.scale.set(1.5, 1.5, 1.5)
      mesh.material.emissiveIntensity = 0.7
    }

    // Focus camera on node
    this.controls.target.set(node.x, node.y, node.z)

    // Notify LiveView
    this.pushEvent("node_selected", {
      id: node.id,
      pac_id: node.pac_id,
      iteration: node.iteration,
      chosen_model: node.chosen_model,
      meta: node.meta
    })
  },

  selectNodeById(id) {
    const node = this.nodes.find(n => n.id === id)
    if (node) {
      this.selectNode(node)
    }
  },

  clearSelection() {
    if (this.selectedNode) {
      const mesh = this.nodeObjects.get(this.selectedNode.id)
      if (mesh) {
        mesh.scale.set(1, 1, 1)
        mesh.material.emissiveIntensity = 0.3
      }
      this.selectedNode = null
      this.pushEvent("node_deselected", {})
    }
  },

  onResize() {
    const container = this.el
    const width = container.clientWidth
    const height = container.clientHeight || 500

    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    this.renderer.setSize(width, height)
  },

  animate() {
    this.animationId = requestAnimationFrame(() => this.animate())

    // Update controls
    this.controls.update()

    // Animate particles
    if (this.particles) {
      this.particles.rotation.y += 0.0002
    }

    // Pulse selected node
    if (this.selectedNode) {
      const mesh = this.nodeObjects.get(this.selectedNode.id)
      if (mesh) {
        const scale = 1.5 + Math.sin(Date.now() * 0.003) * 0.1
        mesh.scale.set(scale, scale, scale)
      }
    }

    // Render
    this.renderer.render(this.scene, this.camera)
  }
}
