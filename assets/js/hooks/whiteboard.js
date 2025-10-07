/**
 * Whiteboard Canvas Hook
 * 
 * Handles real-time collaborative drawing with:
 * - Mouse and touch event handling
 * - Local and remote stroke rendering
 * - Pen and eraser tools
 * - Cursor tracking
 * - Canvas clearing
 */
export const Whiteboard = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.drawing = false;
    this.currentStroke = [];
    
    // Set canvas size to match container
    this.resizeCanvas();
    window.addEventListener("resize", () => this.resizeCanvas());
    
    // Get drawing settings from data attributes
    this.updateSettings();
    
    // Mouse events
    this.canvas.addEventListener("mousedown", (e) => this.startStroke(e));
    this.canvas.addEventListener("mousemove", (e) => {
      this.drawStroke(e);
      this.updateCursor(e);
    });
    this.canvas.addEventListener("mouseup", (e) => this.endStroke(e));
    this.canvas.addEventListener("mouseleave", (e) => this.endStroke(e));
    
    // Touch events
    this.canvas.addEventListener("touchstart", (e) => {
      e.preventDefault();
      this.startStroke(this.getTouchPos(e));
    });
    this.canvas.addEventListener("touchmove", (e) => {
      e.preventDefault();
      this.drawStroke(this.getTouchPos(e));
    });
    this.canvas.addEventListener("touchend", (e) => {
      e.preventDefault();
      this.endStroke(e);
    });
    
    // Handle remote strokes from server
    this.handleEvent("draw_stroke", (stroke) => {
      this.renderRemoteStroke(stroke);
    });
    
    // Handle canvas clear
    this.handleEvent("clear_canvas", () => {
      this.clearCanvas();
    });
    
    console.log("Whiteboard canvas initialized");
  },
  
  updated() {
    // Update settings when LiveView assigns change
    this.updateSettings();
  },
  
  resizeCanvas() {
    const rect = this.canvas.getBoundingClientRect();
    this.canvas.width = rect.width;
    this.canvas.height = rect.height;
    
    // Clear and redraw when resized (strokes are lost on resize)
    this.ctx.fillStyle = "#ffffff";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
  },
  
  updateSettings() {
    this.color = this.canvas.dataset.color || "#000000";
    this.lineWidth = parseInt(this.canvas.dataset.width) || 2;
    this.tool = this.canvas.dataset.tool || "pen";
  },
  
  getMousePos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: e.clientX - rect.left,
      y: e.clientY - rect.top
    };
  },
  
  getTouchPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    const touch = e.touches[0] || e.changedTouches[0];
    return {
      x: touch.clientX - rect.left,
      y: touch.clientY - rect.top
    };
  },
  
  startStroke(e) {
    this.drawing = true;
    const pos = e.offsetX !== undefined ? { x: e.offsetX, y: e.offsetY } : this.getMousePos(e);
    this.currentStroke = [pos];
  },
  
  drawStroke(e) {
    if (!this.drawing) return;
    
    const pos = e.offsetX !== undefined ? { x: e.offsetX, y: e.offsetY } : this.getMousePos(e);
    this.currentStroke.push(pos);
    
    // Draw locally
    if (this.currentStroke.length >= 2) {
      const prev = this.currentStroke[this.currentStroke.length - 2];
      this.renderStroke([prev, pos], this.color, this.lineWidth, this.tool);
    }
  },
  
  endStroke(e) {
    if (!this.drawing) return;
    this.drawing = false;
    
    // Send stroke to server
    if (this.currentStroke.length > 0) {
      this.pushEvent("stroke", {
        points: this.currentStroke.map(p => [p.x, p.y]),
        color: this.color,
        width: this.lineWidth,
        tool: this.tool
      });
    }
    
    this.currentStroke = [];
  },
  
  updateCursor(e) {
    const pos = this.getMousePos(e);
    
    // Throttle cursor updates (every 100ms)
    if (!this.lastCursorUpdate || Date.now() - this.lastCursorUpdate > 100) {
      this.pushEvent("cursor_move", {
        x: Math.round(pos.x),
        y: Math.round(pos.y)
      });
      this.lastCursorUpdate = Date.now();
    }
  },
  
  renderStroke(points, color, width, tool = "pen") {
    if (points.length < 2) return;
    
    this.ctx.beginPath();
    
    if (tool === "eraser") {
      this.ctx.globalCompositeOperation = "destination-out";
      this.ctx.lineWidth = width * 3; // Eraser is wider
    } else {
      this.ctx.globalCompositeOperation = "source-over";
      this.ctx.strokeStyle = color;
      this.ctx.lineWidth = width;
    }
    
    this.ctx.lineCap = "round";
    this.ctx.lineJoin = "round";
    
    // Draw smooth line
    const start = Array.isArray(points[0]) ? 
      { x: points[0][0], y: points[0][1] } : 
      points[0];
    
    this.ctx.moveTo(start.x, start.y);
    
    for (let i = 1; i < points.length; i++) {
      const point = Array.isArray(points[i]) ? 
        { x: points[i][0], y: points[i][1] } : 
        points[i];
      this.ctx.lineTo(point.x, point.y);
    }
    
    this.ctx.stroke();
    
    // Reset composite operation
    this.ctx.globalCompositeOperation = "source-over";
  },
  
  renderRemoteStroke(stroke) {
    const points = stroke.points.map(p => ({ x: p[0], y: p[1] }));
    this.renderStroke(points, stroke.color, stroke.width, stroke.tool || "pen");
  },
  
  clearCanvas() {
    this.ctx.fillStyle = "#ffffff";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
  }
};
