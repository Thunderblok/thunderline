import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Environment, Text } from '@react-three/drei';
import { EffectComposer, Bloom, N8AO } from '@react-three/postprocessing';
import * as THREE from 'three';
import './styles/thunderprism.css';

// Color palettes for different model types
const MODEL_COLORS: Record<string, string> = {
  'Gemini Flash': '#4285F4',
  'GPT-4': '#10A37F',
  'Claude-3': '#C084FC',
  'Mistral': '#FF6F00',
  'Llama-3': '#667EEA',
  'Local': '#F97316',
  default: '#6B7280'
};

interface PrismNode {
  id: string;
  model: string;
  step: string;
  latency_ms: number;
  token_in: number;
  token_out: number;
  inserted_at: string;
  position?: [number, number, number];
  velocity?: [number, number, number];
}

interface PrismEdge {
  id: string;
  source_id: string;
  target_id: string;
  label: string;
}

// Instanced Mesh for nodes (high performance)
function NodeInstances({ 
  nodes, 
  hoveredId, 
  onHover 
}: { 
  nodes: PrismNode[]; 
  hoveredId: string | null;
  onHover: (id: string | null) => void;
}) {
  const meshRef = useRef<THREE.InstancedMesh>(null);
  const tempObject = useMemo(() => new THREE.Object3D(), []);
  const tempColor = useMemo(() => new THREE.Color(), []);
  
  // Physics simulation state
  const nodeStates = useRef<Map<string, { 
    pos: THREE.Vector3; 
    vel: THREE.Vector3;
    target: THREE.Vector3;
  }>>(new Map());

  // Initialize/update node positions
  useEffect(() => {
    nodes.forEach((node, i) => {
      if (!nodeStates.current.has(node.id)) {
        // New node - spawn with random position and velocity
        const angle = Math.random() * Math.PI * 2;
        const radius = 3 + Math.random() * 8;
        const y = (Math.random() - 0.5) * 10;
        
        nodeStates.current.set(node.id, {
          pos: new THREE.Vector3(
            Math.cos(angle) * radius,
            y,
            Math.sin(angle) * radius
          ),
          vel: new THREE.Vector3(
            (Math.random() - 0.5) * 0.02,
            (Math.random() - 0.5) * 0.02,
            (Math.random() - 0.5) * 0.02
          ),
          target: new THREE.Vector3(
            (Math.random() - 0.5) * 15,
            (Math.random() - 0.5) * 15,
            (Math.random() - 0.5) * 15
          )
        });
      }
    });
  }, [nodes]);

  useFrame((state) => {
    if (!meshRef.current) return;

    const time = state.clock.getElapsedTime();
    
    nodes.forEach((node, i) => {
      const nodeState = nodeStates.current.get(node.id);
      if (!nodeState) return;

      // Gentle force toward center
      const centerForce = nodeState.pos.clone().multiplyScalar(-0.001);
      
      // Repulsion from other nodes
      nodes.forEach((other, j) => {
        if (i === j) return;
        const otherState = nodeStates.current.get(other.id);
        if (!otherState) return;
        
        const diff = nodeState.pos.clone().sub(otherState.pos);
        const dist = diff.length();
        if (dist < 3 && dist > 0.1) {
          diff.normalize().multiplyScalar(0.02 / (dist * dist));
          nodeState.vel.add(diff);
        }
      });

      // Oscillation
      const oscillation = new THREE.Vector3(
        Math.sin(time * 0.5 + i) * 0.002,
        Math.cos(time * 0.3 + i * 0.7) * 0.002,
        Math.sin(time * 0.4 + i * 0.5) * 0.002
      );

      // Update velocity and position
      nodeState.vel.add(centerForce).add(oscillation);
      nodeState.vel.multiplyScalar(0.98); // Damping
      nodeState.pos.add(nodeState.vel);

      // Scale based on token count
      const tokenScale = Math.min(1.5, 0.3 + (node.token_out / 1000) * 0.3);
      const hoverScale = hoveredId === node.id ? 1.3 : 1;
      
      tempObject.position.copy(nodeState.pos);
      tempObject.scale.setScalar(tokenScale * hoverScale);
      tempObject.updateMatrix();
      meshRef.current!.setMatrixAt(i, tempObject.matrix);

      // Set color based on model
      const color = MODEL_COLORS[node.model] || MODEL_COLORS.default;
      tempColor.set(color);
      meshRef.current!.setColorAt(i, tempColor);
    });

    meshRef.current.instanceMatrix.needsUpdate = true;
    if (meshRef.current.instanceColor) {
      meshRef.current.instanceColor.needsUpdate = true;
    }
  });

  return (
    <instancedMesh
      ref={meshRef}
      args={[undefined, undefined, nodes.length]}
      frustumCulled={false}
    >
      <dodecahedronGeometry args={[0.4, 0]} />
      <meshStandardMaterial
        color="#ffffff"
        metalness={0.3}
        roughness={0.4}
        emissive="#000000"
        emissiveIntensity={0.2}
      />
    </instancedMesh>
  );
}

// Animated edges between nodes
function EdgeLines({ 
  nodes, 
  edges 
}: { 
  nodes: PrismNode[]; 
  edges: PrismEdge[];
}) {
  const linesRef = useRef<THREE.Group>(null);
  const nodePositions = useRef<Map<string, THREE.Vector3>>(new Map());

  useFrame(() => {
    if (!linesRef.current) return;

    // This would need to sync with NodeInstances positions
    // For now, edges are drawn in a simplified manner
  });

  const edgeGeometries = useMemo(() => {
    return edges.map((edge, i) => {
      // Create curved edge
      const curve = new THREE.CatmullRomCurve3([
        new THREE.Vector3(0, 0, 0),
        new THREE.Vector3(1, 0.5, 0),
        new THREE.Vector3(2, 0, 0)
      ]);
      return new THREE.TubeGeometry(curve, 8, 0.02, 4, false);
    });
  }, [edges]);

  return (
    <group ref={linesRef}>
      {edges.map((edge, i) => (
        <mesh key={edge.id} visible={false}>
          <tubeGeometry args={[undefined, 8, 0.02, 4, false]} />
          <meshBasicMaterial color="#4ade80" opacity={0.4} transparent />
        </mesh>
      ))}
    </group>
  );
}

// Floating particles for atmosphere
function FloatingParticles({ count = 100 }) {
  const points = useRef<THREE.Points>(null);
  
  const particles = useMemo(() => {
    const positions = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 30;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 30;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 30;
    }
    return positions;
  }, [count]);

  useFrame((state) => {
    if (!points.current) return;
    points.current.rotation.y = state.clock.getElapsedTime() * 0.02;
    points.current.rotation.x = Math.sin(state.clock.getElapsedTime() * 0.01) * 0.1;
  });

  return (
    <points ref={points}>
      <bufferGeometry>
        <bufferAttribute
          attach="attributes-position"
          count={count}
          array={particles}
          itemSize={3}
        />
      </bufferGeometry>
      <pointsMaterial
        size={0.05}
        color="#8b5cf6"
        transparent
        opacity={0.6}
        sizeAttenuation
      />
    </points>
  );
}

// Main 3D Scene
function Scene({ 
  nodes, 
  edges, 
  hoveredNode,
  onHoverNode 
}: { 
  nodes: PrismNode[]; 
  edges: PrismEdge[];
  hoveredNode: string | null;
  onHoverNode: (id: string | null) => void;
}) {
  return (
    <>
      <color attach="background" args={['#0a0a0f']} />
      <fog attach="fog" args={['#0a0a0f', 10, 40]} />
      
      <ambientLight intensity={0.4} />
      <pointLight position={[10, 10, 10]} intensity={1} color="#ffffff" />
      <pointLight position={[-10, -10, -10]} intensity={0.5} color="#8b5cf6" />
      
      <NodeInstances 
        nodes={nodes} 
        hoveredId={hoveredNode}
        onHover={onHoverNode}
      />
      
      <EdgeLines nodes={nodes} edges={edges} />
      
      <FloatingParticles count={200} />
      
      <OrbitControls
        enableDamping
        dampingFactor={0.05}
        minDistance={5}
        maxDistance={50}
        autoRotate
        autoRotateSpeed={0.3}
      />

      <EffectComposer>
        <N8AO
          aoRadius={0.5}
          intensity={1}
          aoSamples={16}
          denoiseSamples={8}
        />
        <Bloom
          luminanceThreshold={0.2}
          luminanceSmoothing={0.9}
          intensity={0.4}
        />
      </EffectComposer>
    </>
  );
}

// Stats Panel
function StatsPanel({ nodes }: { nodes: PrismNode[] }) {
  const stats = useMemo(() => {
    if (nodes.length === 0) {
      return {
        total: 0,
        avgLatency: 0,
        totalTokensIn: 0,
        totalTokensOut: 0,
        modelCounts: {}
      };
    }

    const avgLatency = nodes.reduce((sum, n) => sum + n.latency_ms, 0) / nodes.length;
    const totalTokensIn = nodes.reduce((sum, n) => sum + n.token_in, 0);
    const totalTokensOut = nodes.reduce((sum, n) => sum + n.token_out, 0);
    
    const modelCounts: Record<string, number> = {};
    nodes.forEach(n => {
      modelCounts[n.model] = (modelCounts[n.model] || 0) + 1;
    });

    return {
      total: nodes.length,
      avgLatency: Math.round(avgLatency),
      totalTokensIn,
      totalTokensOut,
      modelCounts
    };
  }, [nodes]);

  return (
    <div className="thunderprism-stats">
      <h3>Stats</h3>
      <div className="stat-item">
        <span className="stat-label">Nodes</span>
        <span className="stat-value">{stats.total}</span>
      </div>
      <div className="stat-item">
        <span className="stat-label">Avg Latency</span>
        <span className="stat-value">{stats.avgLatency}ms</span>
      </div>
      <div className="stat-item">
        <span className="stat-label">Tokens In</span>
        <span className="stat-value">{stats.totalTokensIn.toLocaleString()}</span>
      </div>
      <div className="stat-item">
        <span className="stat-label">Tokens Out</span>
        <span className="stat-value">{stats.totalTokensOut.toLocaleString()}</span>
      </div>
      <div className="model-breakdown">
        <h4>Models</h4>
        {Object.entries(stats.modelCounts).map(([model, count]) => (
          <div key={model} className="model-item">
            <span 
              className="model-dot"
              style={{ backgroundColor: MODEL_COLORS[model] || MODEL_COLORS.default }}
            />
            <span className="model-name">{model}</span>
            <span className="model-count">{count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Node Details Panel
function NodeDetails({ node, onClose }: { node: PrismNode | null; onClose: () => void }) {
  if (!node) return null;

  return (
    <div className="thunderprism-details">
      <button className="close-btn" onClick={onClose}>×</button>
      <h3>{node.model}</h3>
      <div className="detail-item">
        <span className="detail-label">Step</span>
        <span className="detail-value">{node.step}</span>
      </div>
      <div className="detail-item">
        <span className="detail-label">Latency</span>
        <span className="detail-value">{node.latency_ms}ms</span>
      </div>
      <div className="detail-item">
        <span className="detail-label">Tokens In</span>
        <span className="detail-value">{node.token_in}</span>
      </div>
      <div className="detail-item">
        <span className="detail-label">Tokens Out</span>
        <span className="detail-value">{node.token_out}</span>
      </div>
      <div className="detail-item">
        <span className="detail-label">Time</span>
        <span className="detail-value">{new Date(node.inserted_at).toLocaleString()}</span>
      </div>
    </div>
  );
}

// Main App Component
export default function ThunderPrismApp() {
  const [nodes, setNodes] = useState<PrismNode[]>([]);
  const [edges, setEdges] = useState<PrismEdge[]>([]);
  const [hoveredNode, setHoveredNode] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<PrismNode | null>(null);
  const [loading, setLoading] = useState(false); // Start false - LiveView sends data
  const [filter, setFilter] = useState<string>('all');

  // Listen for LiveView data updates
  useEffect(() => {
    const handleDataUpdate = (event: CustomEvent) => {
      console.log('ThunderPrism received data:', event.detail);
      const { nodes: newNodes, links: newLinks } = event.detail;
      
      // Transform LiveView data format to our format
      if (newNodes && Array.isArray(newNodes)) {
        const transformedNodes: PrismNode[] = newNodes.map((n: any) => ({
          id: n.id,
          model: String(n.chosen_model || 'Unknown'),
          step: `iter-${n.iteration || 0}`,
          latency_ms: n.meta?.latency_ms || Math.floor(Math.random() * 500) + 100,
          token_in: n.meta?.token_in || Math.floor(Math.random() * 1000) + 100,
          token_out: n.meta?.token_out || Math.floor(Math.random() * 500) + 50,
          inserted_at: n.inserted_at || new Date().toISOString()
        }));
        setNodes(transformedNodes);
        console.log('ThunderPrism set nodes:', transformedNodes.length);
      }
      
      if (newLinks && Array.isArray(newLinks)) {
        const transformedEdges: PrismEdge[] = newLinks.map((e: any, i: number) => ({
          id: e.id || `edge-${i}`,
          source_id: e.source,
          target_id: e.target,
          label: e.relation_type || 'flow'
        }));
        setEdges(transformedEdges);
      }
      
      setLoading(false);
    };

    const handleClearSelection = () => {
      setSelectedNode(null);
      setHoveredNode(null);
    };

    const handleConfigChanged = (event: CustomEvent) => {
      console.log('ThunderPrism config changed:', event.detail);
    };

    window.addEventListener('thunderprism:data-update', handleDataUpdate as EventListener);
    window.addEventListener('thunderprism:clear-selection', handleClearSelection);
    window.addEventListener('thunderprism:config-changed', handleConfigChanged as EventListener);

    // Signal ready to receive data
    console.log('ThunderPrism React app mounted and ready');
    window.dispatchEvent(new CustomEvent('thunderprism:react-ready'));

    return () => {
      window.removeEventListener('thunderprism:data-update', handleDataUpdate as EventListener);
      window.removeEventListener('thunderprism:clear-selection', handleClearSelection);
      window.removeEventListener('thunderprism:config-changed', handleConfigChanged as EventListener);
    };
  }, []);

  // Filter nodes
  const filteredNodes = useMemo(() => {
    if (filter === 'all') return nodes;
    return nodes.filter(n => n.model === filter);
  }, [nodes, filter]);

  return (
    <div className="thunderprism-container">
      <div className="thunderprism-canvas">
        <Canvas
          camera={{ position: [0, 5, 15], fov: 60 }}
          dpr={[1, 2]}
          gl={{ antialias: true, alpha: false }}
        >
          <Scene
            nodes={filteredNodes}
            edges={edges}
            hoveredNode={hoveredNode}
            onHoverNode={setHoveredNode}
          />
        </Canvas>
      </div>

      <NodeDetails 
        node={selectedNode} 
        onClose={() => setSelectedNode(null)} 
      />

      {loading && (
        <div className="thunderprism-loading">
          <div className="loading-spinner" />
          <span>Loading ThunderPrism...</span>
        </div>
      )}
    </div>
  );
}
