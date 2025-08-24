import React, { useMemo, useState } from "react";

/**
 * OKO Dashboard Mockup — Adjusted Layout
 * - Friends list on left
 * - KPIs + Event feed in center
 * - Faux-3D Domain Map + Inspector on right (moved up above lines)
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

  return (
    <div className="min-h-screen bg-black text-white">
      <style>{`
        @keyframes dash { to { stroke-dashoffset: -1000; } }
        .flow { stroke-dasharray: 6 10; animation: dash 8s linear infinite; }
        .flow.slow { animation-duration: 12s; }
        .flow.fast { animation-duration: 5s; }
      `}</style>

      <div className="grid grid-cols-12 gap-4 p-4 relative z-10">
        {/* Friends list */}
        <aside className="col-span-12 md:col-span-3 xl:col-span-3 bg-neutral-900/60 border border-neutral-800 rounded-xl p-3">
          <h2 className="font-semibold mb-2">Friends</h2>
          {friends.map((f) => (
            <button
              key={f.id}
              onClick={() => setActiveFriend(f.id)}
              className={`w-full text-left px-3 py-2 rounded-lg border border-neutral-800 mb-1 ${
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
                <span>{f.name}</span>
                <span className="ml-auto text-xs opacity-60">{f.status}</span>
              </div>
            </button>
          ))}
        </aside>

        {/* KPIs */}
        <main className="col-span-12 md:col-span-5 xl:col-span-5 space-y-4">
          <div className="bg-neutral-900/60 border border-neutral-800 rounded-xl p-4 relative z-20">
            <h2 className="font-semibold mb-2">KPIs</h2>
            <div className="grid grid-cols-3 gap-3">
              <div>Ops/min: 4500</div>
              <div>Domains: 27</div>
              <div>Latency p95: 128ms</div>
            </div>
          </div>

          <div className="bg-neutral-900/60 border border-neutral-800 rounded-xl p-4 h-72 overflow-auto relative z-20">
            <h3 className="font-semibold mb-2">Event Flow</h3>
            <ul className="space-y-2 text-sm">
              {edges.map((e, i) => (
                <li key={i} className="border border-neutral-800 rounded-lg p-2">
                  {e.a} → {e.b} traffic {Math.round(e.traffic * 100)}%
                </li>
              ))}
            </ul>
          </div>
        </main>

        {/* Domain Map + Inspector */}
        <section className="col-span-12 md:col-span-4 xl:col-span-4 space-y-4">
          <div className="bg-neutral-900/60 border border-neutral-800 rounded-xl p-4 relative z-20">
            <h3 className="font-semibold mb-3">Domain Map</h3>
            <SvgMap
              nodes={domains}
              edges={edges}
              selectedId={selectedDomain}
              onSelect={(id) => setSelectedDomain(id)}
              health={health}
            />
          </div>

          <div className="bg-neutral-900/60 border border-neutral-800 rounded-xl p-4 relative z-20">
            <h3 className="font-semibold mb-2">Inspector</h3>
            {selected ? (
              <InspectorCard domain={selected} h={health[selected.id]} />
            ) : (
              <div className="text-sm opacity-60">Click a node to inspect metrics.</div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

function InspectorCard({ domain, h }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <span className="text-xs uppercase">{h?.status}</span>
        <div className="text-lg font-semibold">{domain.label}</div>
      </div>
      <div className="grid grid-cols-3 gap-2 text-sm">
        <Metric label="Ops/min" value={h?.ops} />
        <Metric label="CPU%" value={h?.cpu} />
        <Metric label="p95" value={`${h?.p95}ms`} />
      </div>
      <p className="text-xs opacity-50">Errors: {h?.errors}</p>
    </div>
  );
}

function Metric({ label, value }) {
  return (
    <div className="p-2 rounded bg-neutral-800/40">
      <div className="text-xs opacity-60">{label}</div>
      <div>{value}</div>
    </div>
  );
}

function SvgMap({ nodes, edges, selectedId, onSelect, health }) {
  const pathFor = (a, b) => {
    const c1x = (a.x + b.x) / 2;
    const c1y = a.y - 60 - a.z * 2;
    const c2x = (a.x + b.x) / 2;
    const c2y = b.y + 60 + b.z * 2;
    return `M ${a.x},${a.y} C ${c1x},${c1y} ${c2x},${c2y} ${b.x},${b.y}`;
  };
  const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));
  return (
    <svg viewBox="0 0 760 360" className="w-full h-full rounded-xl bg-neutral-900/40 relative z-0">
      <defs>
        <linearGradient id="wire" x1="0" x2="1">
          <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.9" />
          <stop offset="100%" stopColor="#10b981" stopOpacity="0.9" />
        </linearGradient>
      </defs>
      {edges.map((e, i) => {
        const a = byId[e.a];
        const b = byId[e.b];
        return <path key={i} d={pathFor(a, b)} stroke="url(#wire)" strokeWidth={2} fill="none" className="flow"/>;
      })}
      {nodes.map((n) => (
        <g key={n.id} className="cursor-pointer" onClick={() => onSelect?.(n.id)}>
          <circle cx={n.x} cy={n.y} r={14} fill="#22d3ee" />
          <text x={n.x + 20} y={n.y + 4} fontSize={12} fill="#e5e7eb">{n.label}</text>
        </g>
      ))}
    </svg>
  );
}
