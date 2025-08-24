import React, { useMemo, useState } from "react";

/**
 * OKO Dashboard Mockup — No external deps (Tailwind+daisyUI only)
 * - Left: Friends list (DMs)
 * - Center: KPIs + Activity (filters by selected domain)
 * - Right: Faux-3D Domain Map (SVG) with animated Bezier links
 *   + Click a node to open the Inspector (health, actions)
 */

export default function OkoMockup() {
  const [activeFriend, setActiveFriend] = useState("sarah");
  const [selectedDomain, setSelectedDomain] = useState(null);

  const friends = [
    { id: "sarah", name: "Sarah Connor", status: "online" },
    { id: "mike", name: "Mike Johnson", status: "away" },
    { id: "nik", name: "Nikolai Tesla", status: "online" },
    { id: "rip", name: "Ripley", status: "busy" },
    { id: "neo", name: "Neo", status: "offline" },
  ];

  // Domain nodes (with lightweight health snapshot)
  const domains = useMemo(
    () => [
      { id: "oko-ai", label: "oko.ai", x: 140, y: 90, z: 18 },
      { id: "grid", label: "thundergrid", x: 380, y: 150, z: 4 },
      { id: "bolt", label: "thunderbolt", x: 620, y: 90, z: 10 },
      { id: "block", label: "thunderblock", x: 520, y: 260, z: 0 },
      { id: "mnesia", label: "mnesia", x: 230, y: 250, z: -6 },
    ],
    []
  );

  const health = useMemo(
    () => ({
      "oko-ai": { status: "healthy", ops: 920, cpu: 28, p95: 112, errors: 0 },
      grid: { status: "warning", ops: 710, cpu: 63, p95: 188, errors: 2 },
      bolt: { status: "healthy", ops: 560, cpu: 41, p95: 129, errors: 0 },
      block: { status: "healthy", ops: 330, cpu: 22, p95: 144, errors: 1 },
      mnesia: { status: "critical", ops: 480, cpu: 77, p95: 240, errors: 4 },
    }),
    []
  );

  // Directed edges (source -> target)
  const edges = useMemo(
    () => [
      { a: "oko-ai", b: "grid", traffic: 0.8 },
      { a: "grid", b: "bolt", traffic: 0.6 },
      { a: "bolt", b: "block", traffic: 0.4 },
      { a: "grid", b: "mnesia", traffic: 0.7 },
      { a: "mnesia", b: "oko-ai", traffic: 0.5 },
    ],
    []
  );

  const selected = selectedDomain
    ? domains.find((d) => d.id === selectedDomain)
    : null;

  // Activity feed (demo data filtered by selected domain)
  const events = useMemo(() => {
    const base = [
      { from: "grid", to: "bolt", n: 71 },
      { from: "bolt", to: "block", n: 44 },
      { from: "grid", to: "mnesia", n: 59 },
      { from: "mnesia", to: "oko-ai", n: 22 },
      { from: "oko-ai", to: "grid", n: 83 },
      { from: "block", to: "grid", n: 35 },
      { from: "oko-ai", to: "bolt", n: 18 },
      { from: "bolt", to: "oko-ai", n: 27 },
      { from: "mnesia", to: "grid", n: 51 },
      { from: "grid", to: "block", n: 64 },
      { from: "block", to: "bolt", n: 19 },
      { from: "oko-ai", to: "mnesia", n: 14 },
    ];
    if (!selectedDomain) return base;
    return base.filter((e) => e.from === selectedDomain || e.to === selectedDomain);
  }, [selectedDomain]);

  return (
    <div className="min-h-screen bg-[#0B0F14] text-white">
      <style>{`
        @keyframes dash { to { stroke-dashoffset: -1000; } }
        .flow { stroke-dasharray: 6 10; animation: dash 8s linear infinite; }
        .flow.slow { animation-duration: 12s; }
        .flow.fast { animation-duration: 5s; }
        .node-glow { filter: drop-shadow(0 0 8px rgba(16,185,129,.6)); }
        .panel { @apply bg-white/5 backdrop-blur-xl border border-white/10 rounded-2xl; }
      `}</style>

      {/* Top bar */}
      <header className="sticky top-0 z-10 bg-gradient-to-r from-white/5 to-transparent backdrop-blur border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 py-3 flex items-center gap-4">
          <div className="text-sm uppercase tracking-widest text-emerald-300">OKO High Command</div>
          <div className="text-lg font-semibold">Operations Dashboard</div>
          <div className="ml-auto flex items-center gap-2 text-sm text-white/70">
            <span className="hidden sm:inline">Status:</span>
            <span className="px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-300/30">Green</span>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto grid grid-cols-12 gap-4 p-4">
        {/* Friends / DM list */}
        <aside className="col-span-12 md:col-span-3 xl:col-span-3 panel p-3">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-2 h-2 rounded-full bg-emerald-400" />
            <h2 className="font-semibold">Friends</h2>
          </div>
          <div className="space-y-1">
            {friends.map((f) => (
              <button
                key={f.id}
                onClick={() => setActiveFriend(f.id)}
                className={`w-full text-left px-3 py-2 rounded-xl transition border border-white/5 hover:bg-white/5 ${
                  activeFriend === f.id ? "bg-white/10" : ""
                }`}
              >
                <div className="flex items-center gap-3">
                  <span
                    className={`w-2 h-2 rounded-full ${
                      f.status === "online"
                        ? "bg-emerald-400"
                        : f.status === "away"
                        ? "bg-amber-400"
                        : f.status === "busy"
                        ? "bg-rose-400"
                        : "bg-slate-500"
                    }`}
                  />
                  <span className="truncate">{f.name}</span>
                  <span className="ml-auto text-xs text-white/50">{f.status}</span>
                </div>
              </button>
            ))}
          </div>
          <div className="mt-4 grid grid-cols-2 gap-2">
            <button className="btn btn-sm btn-ghost border border-white/10">New Chat</button>
            <button className="btn btn-sm btn-ghost border border-white/10">Create Room</button>
          </div>
        </aside>

        {/* Middle column: controls + activity */}
        <main className="col-span-12 md:col-span-5 xl:col-span-5 space-y-4">
          {/* KPI */}
          <div className="panel p-4">
            <div className="stats stats-vertical lg:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">Ops / min</div>
                <div className="stat-value text-emerald-300">4,500</div>
                <div className="stat-desc text-emerald-400">+2.1% vs last</div>
              </div>
              <div className="stat">
                <div className="stat-title">Domains</div>
                <div className="stat-value">27</div>
                <div className="stat-desc">3 maintenance</div>
              </div>
              <div className="stat">
                <div className="stat-title">Latency (p95)</div>
                <div className="stat-value">128ms</div>
                <div className="stat-desc text-amber-300">watch</div>
              </div>
            </div>
          </div>

          {/* Activity feed */}
          <div className="panel p-4 h-72 overflow-auto">
            <div className="flex items-center gap-2 mb-2">
              <div className="w-2 h-2 rounded-full bg-violet-400" />
              <h3 className="font-semibold">Event Flow</h3>
              <span className="ml-auto text-xs text-white/50">
                {selected ? `filtered: ${selected.label}` : "latest 30"}
              </span>
            </div>
            <ul className="space-y-2 text-sm">
              {events.map((e, i) => (
                <li key={i} className="p-2 rounded-lg bg-white/5 border border-white/10">
                  {e.from} · processed {40 + i} ops → {e.to} · 20:{String(18 + i).padStart(2, "0")}
                </li>
              ))}
            </ul>
          </div>

          {/* Controls */}
          <div className="panel p-4">
            <div className="grid grid-cols-2 gap-3">
              <button className="btn btn-outline">Deploy</button>
              <button className="btn btn-outline">Restart Node</button>
              <button className="btn btn-outline">Open Logs</button>
              <button className="btn btn-outline">Settings</button>
            </div>
          </div>
        </main>

        {/* Right column: Domain Map + Inspector */}
        <section className="col-span-12 md:col-span-4 xl:col-span-4 space-y-4">
          <div className="panel p-4">
            <div className="flex items-center gap-2 mb-3">
              <div className="w-2 h-2 rounded-full bg-cyan-400" />
              <h3 className="font-semibold">Domain Map</h3>
              <span className="ml-auto text-xs text-white/50">3D view (simulated)</span>
            </div>
            <div className="relative w-full h-[420px]">
              <SvgMap
                nodes={domains}
                edges={edges}
                selectedId={selectedDomain}
                onSelect={(id) => setSelectedDomain(id)}
                health={health}
              />
            </div>
          </div>

          {/* Inspector */}
          <div className="panel p-4">
            <div className="flex items-center gap-2 mb-2">
              <div className="w-2 h-2 rounded-full bg-emerald-400" />
              <h3 className="font-semibold">Inspector</h3>
              <span className="ml-auto text-xs text-white/50">
                {selected ? selected.label : "select a node"}
              </span>
            </div>

            {selected ? (
              <InspectorCard domain={selected} h={health[selected.id]} />
            ) : (
              <div className="text-sm text-white/60">Click a node on the map to inspect health, metrics and actions.</div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

function InspectorCard({ domain, h }) {
  const badge =
    h?.status === "healthy"
      ? "badge-success"
      : h?.status === "warning"
      ? "badge-warning"
      : "badge-error";

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <div className={`badge ${badge} badge-outline`}>{h?.status || "unknown"}</div>
        <div className="text-lg font-semibold">{domain.label}</div>
      </div>

      {/* mini sparkline */}
      <Sparkline values={[h?.ops || 0, h?.ops * 0.9, h?.ops * 1.1, h?.ops * 0.95, (h?.ops || 0) + 30]} />

      <div className="grid grid-cols-3 gap-2 text-sm">
        <Metric label="Ops/min" value={h?.ops} />
        <Metric label="CPU%" value={h?.cpu} />
        <Metric label="p95" value={`${h?.p95}ms`} />
      </div>

      <div className="grid grid-cols-2 gap-2">
        <button className="btn btn-sm btn-outline">Open Logs</button>
        <button className="btn btn-sm btn-outline">Restart</button>
        <button className="btn btn-sm btn-outline">Tail Metrics</button>
        <button className="btn btn-sm btn-outline">Quarantine</button>
      </div>
    </div>
  );
}

function Metric({ label, value }) {
  return (
    <div className="p-2 rounded-lg bg-white/5 border border-white/10">
      <div className="text-xs text-white/50">{label}</div>
      <div className="text-base">{value}</div>
    </div>
  );
}

function Sparkline({ values }) {
  const max = Math.max(...values);
  const pts = values
    .map((v, i) => `${(i / (values.length - 1)) * 100},${100 - (v / max) * 100}`)
    .join(" ");
  return (
    <svg viewBox="0 0 100 100" className="w-full h-10">
      <polyline points={pts} fill="none" stroke="#34d399" strokeWidth="2" />
    </svg>
  );
}

function SvgMap({ nodes, edges, selectedId, onSelect, health }) {
  // Calculate cubic bezier path between two points with gentle arch; z depth nudges the control points
  const pathFor = (a, b) => {
    const c1x = (a.x + b.x) / 2;
    const c1y = a.y - 60 - a.z * 2;
    const c2x = (a.x + b.x) / 2;
    const c2y = b.y + 60 + b.z * 2;
    return `M ${a.x},${a.y} C ${c1x},${c1y} ${c2x},${c2y} ${b.x},${b.y}`;
  };

  const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));

  const connected = (id) =>
    edges.some((e) => e.a === id || e.b === id);

  const isEdgeHot = (e) =>
    !selectedId || e.a === selectedId || e.b === selectedId;

  const statusColor = (id) => {
    const s = health?.[id]?.status;
    if (s === "healthy") return "#34d399";
    if (s === "warning") return "#f59e0b";
    if (s === "critical") return "#f43f5e";
    return "#94a3b8";
  };

  return (
    <svg viewBox="0 0 760 360" className="w-full h-full rounded-xl bg-gradient-to-b from-slate-900/40 to-slate-900/10">
      {/* background glow grid */}
      <defs>
        <linearGradient id="wire" x1="0" x2="1">
          <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.9" />
          <stop offset="100%" stopColor="#10b981" stopOpacity="0.9" />
        </linearGradient>
        <filter id="blur"><feGaussianBlur stdDeviation="6" /></filter>
      </defs>

      {/* faint perspective grid */}
      {[...Array(12)].map((_, i) => (
        <line key={`g${i}`} x1={40} y1={30 + i * 26} x2={720} y2={10 + i * 26}
          stroke="#1f2937" strokeWidth={1} opacity={0.45} />
      ))}

      {/* edges */}
      {edges.map((e, i) => {
        const a = byId[e.a];
        const b = byId[e.b];
        const path = pathFor(a, b);
        const speed = e.traffic > 0.7 ? "fast" : e.traffic < 0.5 ? "slow" : "";
        const hot = isEdgeHot(e);
        return (
          <g key={`edge-${i}`}>
            <path d={path} stroke="#0ea5e9" strokeOpacity={hot ? 0.18 : 0.06} strokeWidth={8} fill="none" filter="url(#blur)" />
            <path d={path} stroke="url(#wire)" strokeWidth={hot ? 2.5 : 1.2} fill="none" className={`flow ${speed}`}>
              <title>{`${e.a} → ${e.b} · traffic ${(e.traffic * 100).toFixed(0)}%`}</title>
            </path>
          </g>
        );
      })}

      {/* nodes */}
      {nodes.map((n) => {
        const selected = n.id === selectedId;
        const ring = selected ? 4 : connected(n.id) ? 2 : 1;
        const color = statusColor(n.id);
        return (
          <g key={n.id} className="cursor-pointer" onClick={() => onSelect?.(n.id)}>
            <circle cx={n.x} cy={n.y} r={14 + ring} fill="none" stroke={color} strokeOpacity={0.35} strokeWidth={ring} />
            <circle cx={n.x} cy={n.y} r={14} fill={color} opacity={0.85} />
            <text x={n.x + 20} y={n.y + 4} fontSize={12} fill="#e5e7eb">{n.label}</text>
          </g>
        );
      })}
    </svg>
  );
}
