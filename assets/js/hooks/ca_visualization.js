/**
 * 3D Cellular Automata Visualization Hook
 * 
 * WebGL-based 3D visualization for ThunderBolt/ThunderBit CA system.
 * Provides real-time rendering of hexagonal grid with interactive controls.
 */

import * as THREE from 'three';

export const CAVisualization = {
  mounted() {
    this.initializeVisualization();
    this.setupEventListeners();
    // Attach LiveView event handler for deltas if not already present
    this.handleEvent && this.handleEvent("ca:update", ({cells}) => {
      if (!cells) return;
      for (const c of cells) {
        const mesh = this.cells && this.cells.get(c.id);
        if (!mesh) continue;
        if (typeof c.hex === 'number') {
          mesh.material.color.setHex(c.hex);
        }
        if (c.energy != null) {
          mesh.userData.energy = c.energy;
        }
        mesh.userData.state = c.state;
      }
    });
  },

  destroyed() {
    this.cleanup();
  },

  initializeVisualization() {
    const canvas = this.el;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;

    // Scene setup
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x000011);

    // Camera setup
    this.camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
    this.camera.position.set(0, 0, 15);

    // Renderer setup
    this.renderer = new THREE.WebGLRenderer({ 
      canvas: canvas, 
      antialias: true,
      alpha: true 
    });
    this.renderer.setSize(width, height);
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    // Lighting setup
    this.setupLighting();

    // Grid setup
    this.gridSize = parseInt(canvas.dataset.gridSize) || 12;
    this.cells = new Map();
    this.setupHexGrid();

    // Controls
    this.setupControls();

    // Animation state
    this.isAnimating = true;
    this.autoRotate = false;
    this.performanceMode = canvas.dataset.performanceMode || 'balanced';

    // Start render loop
    this.animate();

    // Handle resize
    window.addEventListener('resize', () => this.onWindowResize());
  },

  setupLighting() {
    // Ambient light
    const ambientLight = new THREE.AmbientLight(0x404040, 0.3);
    this.scene.add(ambientLight);

    // Directional light
    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(10, 10, 5);
    directionalLight.castShadow = true;
    directionalLight.shadow.mapSize.width = 2048;
    directionalLight.shadow.mapSize.height = 2048;
    this.scene.add(directionalLight);

    // Point lights for atmosphere
    const pointLight1 = new THREE.PointLight(0x00ffff, 0.5, 20);
    pointLight1.position.set(-8, 8, 8);
    this.scene.add(pointLight1);

    const pointLight2 = new THREE.PointLight(0xff00ff, 0.5, 20);
    pointLight2.position.set(8, -8, 8);
    this.scene.add(pointLight2);
  },

  setupHexGrid() {
    this.hexGroup = new THREE.Group();
    this.scene.add(this.hexGroup);

    // Create hex geometry (will be instanced)
    const hexRadius = 0.8;
    this.hexGeometry = new THREE.CylinderGeometry(hexRadius, hexRadius, 0.2, 6);
    
    // Create materials for different states
    this.materials = {
      inactive: new THREE.MeshPhongMaterial({ 
        color: 0x333333, 
        transparent: true, 
        opacity: 0.6 
      }),
      active: new THREE.MeshPhongMaterial({ 
        color: 0x00ff00, 
        emissive: 0x002200 
      }),
      evolving: new THREE.MeshPhongMaterial({ 
        color: 0xffff00, 
        emissive: 0x222200 
      }),
      critical: new THREE.MeshPhongMaterial({ 
        color: 0xff0000, 
        emissive: 0x220000 
      })
    };

    // Initialize hex cells
    this.initializeHexCells();
  },

  initializeHexCells() {
    for (let row = 0; row < this.gridSize; row++) {
      for (let col = 0; col < this.gridSize; col++) {
        const cellId = `${row}-${col}`;
        const position = this.hexCoordinates(row, col);
        
        const mesh = new THREE.Mesh(this.hexGeometry, this.materials.inactive);
        mesh.position.set(position.x, position.y, 0);
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        mesh.userData = { 
          cellId, 
          row, 
          col, 
          state: 'inactive',
          energy: 0 
        };

        // Add click handling
        mesh.onClick = () => this.onCellClick(cellId);

        this.hexGroup.add(mesh);
        this.cells.set(cellId, mesh);
      }
    }
  },

  hexCoordinates(row, col) {
    const hexRadius = 1.5;
    const xOffset = (row % 2) * (hexRadius * 0.5);
    
    return {
      x: (col - this.gridSize / 2) * hexRadius + xOffset,
      y: (row - this.gridSize / 2) * hexRadius * 0.866, // sqrt(3)/2
      z: 0
    };
  },

  setupControls() {
    // Mouse/touch controls for camera
    this.mouse = { x: 0, y: 0 };
    this.isMouseDown = false;
    this.rotation = { x: 0, y: 0 };
    this.zoom = 15;

    const canvas = this.el;

    // Mouse events
    canvas.addEventListener('mousedown', (e) => {
      this.isMouseDown = true;
      this.mouse.x = e.clientX;
      this.mouse.y = e.clientY;
    });

    canvas.addEventListener('mousemove', (e) => {
      if (!this.isMouseDown) return;

      const deltaX = e.clientX - this.mouse.x;
      const deltaY = e.clientY - this.mouse.y;

      this.rotation.y += deltaX * 0.01;
      this.rotation.x += deltaY * 0.01;

      this.mouse.x = e.clientX;
      this.mouse.y = e.clientY;

      this.updateCameraPosition();
    });

    canvas.addEventListener('mouseup', () => {
      this.isMouseDown = false;
    });

    // Zoom with mouse wheel
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.zoom += e.deltaY * 0.01;
      this.zoom = Math.max(5, Math.min(50, this.zoom));
      this.updateCameraPosition();
    });

    // Click detection for cell interaction
    canvas.addEventListener('click', (e) => this.onCanvasClick(e));
  },

  updateCameraPosition() {
    const x = Math.sin(this.rotation.y) * Math.cos(this.rotation.x) * this.zoom;
    const y = Math.sin(this.rotation.x) * this.zoom;
    const z = Math.cos(this.rotation.y) * Math.cos(this.rotation.x) * this.zoom;

    this.camera.position.set(x, y, z);
    this.camera.lookAt(0, 0, 0);
  },

  onCanvasClick(event) {
    // Raycasting for cell selection
    const rect = this.el.getBoundingClientRect();
    const mouse = new THREE.Vector2();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    const raycaster = new THREE.Raycaster();
    raycaster.setFromCamera(mouse, this.camera);

    const intersects = raycaster.intersectObjects(this.hexGroup.children);
    
    if (intersects.length > 0) {
      const clickedMesh = intersects[0].object;
      this.onCellClick(clickedMesh.userData.cellId);
    }
  },

  onCellClick(cellId) {
    // Send cell click event to Hologram
    this.pushEvent('cell_click', { cell_id: cellId });
    
    // Visual feedback
    const mesh = this.cells.get(cellId);
    if (mesh) {
      this.highlightCell(mesh);
    }
  },

  highlightCell(mesh) {
    // Temporary highlight effect
    const originalColor = mesh.material.color.getHex();
    mesh.material.color.setHex(0xffffff);
    
    setTimeout(() => {
      mesh.material.color.setHex(originalColor);
    }, 200);
  },

  animate() {
    if (!this.isAnimating) return;

    requestAnimationFrame(() => this.animate());

    // Auto-rotation
    if (this.autoRotate) {
      this.rotation.y += 0.005;
      this.updateCameraPosition();
    }

    // Update any animated elements
    this.updateAnimations();

    // Render
    this.renderer.render(this.scene, this.camera);

    // Update FPS counter
    this.updateFPS();
  },

  updateAnimations() {
    // Animate active cells with pulsing effect
    const time = Date.now() * 0.001;
    
    this.cells.forEach((mesh, cellId) => {
      if (mesh.userData.state === 'active' || mesh.userData.state === 'evolving') {
        const pulse = Math.sin(time * 3 + Math.random() * Math.PI) * 0.1 + 1;
        mesh.scale.setScalar(pulse);
        
        // Add slight bobbing motion
        const bob = Math.sin(time * 2 + Math.random() * Math.PI) * 0.1;
        mesh.position.z = bob;
      }
    });
  },

  updateFPS() {
    // Simple FPS counter
    if (!this.fpsTime) this.fpsTime = Date.now();
    if (!this.frameCount) this.frameCount = 0;

    this.frameCount++;
    
    if (Date.now() - this.fpsTime >= 1000) {
      const fpsElement = document.getElementById('fps-counter');
      if (fpsElement) {
        fpsElement.textContent = this.frameCount.toString();
      }
      
      this.frameCount = 0;
      this.fpsTime = Date.now();
    }
  },

  setupEventListeners() {
    // Phoenix events from Hologram
    this.handleEvent('update_ca_data', ({ cells }) => {
      this.updateCellData(cells);
    });

    this.handleEvent('reset_camera', () => {
      this.resetCamera();
    });

    this.handleEvent('toggle_auto_rotate', () => {
      this.autoRotate = !this.autoRotate;
    });

    this.handleEvent('set_performance_mode', ({ mode }) => {
      this.setPerformanceMode(mode);
    });

    this.handleEvent('highlight_cell', ({ cell_id }) => {
      const mesh = this.cells.get(cell_id);
      if (mesh) this.highlightCell(mesh);
    });

    this.handleEvent('connection_status', ({ connected }) => {
      this.updateConnectionStatus(connected);
    });
  },

  updateCellData(cells) {
    // Update 3D visualization with new cell data
    cells.forEach(cell => {
      const mesh = this.cells.get(cell.id);
      if (!mesh) return;

      // Update material based on state
      const material = this.materials[cell.state] || this.materials.inactive;
      mesh.material = material;

      // Update position if needed
      if (cell.position) {
        mesh.position.set(...cell.position);
      }

      // Update scale based on energy/size
      if (cell.size) {
        mesh.scale.setScalar(cell.size);
      }

      // Update user data
      mesh.userData.state = cell.state;
      mesh.userData.energy = cell.energy;
    });
  },

  resetCamera() {
    this.rotation = { x: 0, y: 0 };
    this.zoom = 15;
    this.updateCameraPosition();
  },

  setPerformanceMode(mode) {
    this.performanceMode = mode;
    
    // Adjust quality settings based on performance mode
    switch (mode) {
      case 'high':
        this.renderer.setPixelRatio(window.devicePixelRatio);
        this.renderer.shadowMap.enabled = true;
        break;
      case 'balanced':
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        this.renderer.shadowMap.enabled = true;
        break;
      case 'fast':
        this.renderer.setPixelRatio(1);
        this.renderer.shadowMap.enabled = false;
        break;
    }
  },

  updateConnectionStatus(connected) {
    // Visual indicator for connection status
    if (connected) {
      this.scene.background = new THREE.Color(0x000011);
    } else {
      this.scene.background = new THREE.Color(0x110000);
    }
  },

  onWindowResize() {
    const width = this.el.clientWidth;
    const height = this.el.clientHeight;

    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
  },

  cleanup() {
    this.isAnimating = false;
    
    if (this.renderer) {
      this.renderer.dispose();
    }
    
    // Clean up geometries and materials
    if (this.hexGeometry) {
      this.hexGeometry.dispose();
    }
    
    Object.values(this.materials).forEach(material => {
      material.dispose();
    });
    
    window.removeEventListener('resize', this.onWindowResize);
  }
};
