# DIP-VIM-001 — Virtual Ising Machine (VIM) Layer

Status: Draft  
Owners: Thunderline Core (Routing/TOCP), Cerebros Personalization  
Reviewers: High Command @ OKO, ThunderBolt & ThunderFlow Stewards  
Created: 2025-08-30  
Decision Window: 7 days from creation

---
## 1. Summary
Introduce a Virtual Ising Machine (VIM) as a shared optimization layer for:
- **Routing relay selection** in TOCP (exact-K, diversity & anti-correlation aware)
- **Persona “style board” selection** in Cerebros (energy-minimized template/constraint masks)

VIM exposes APIs to define sparse binary quadratic problems (BQM/Ising h, J, constraints), solve them via simulated annealing (SA)/tabu, and inject results into runtime decisions. Entirely feature-flagged, auditable, and degradable to existing heuristics.

---
## 2. Motivation
| Need | Why Ising / BQM Fits |
|------|----------------------|
| Multi-factor routing tradeoffs | Exact-K selection + diversity penalties natural as quadratic penalties |
| Persona/template selection | Binary toggles + co-occurrence couplings = low-latency energy minimization |
| Interpretability | h_i & J_ij inspectable; auditable decision surface |
| Cost & offline viability | Lightweight SA vs large neural inference; aligns with Desolé edge posture |
| Criticality control | Temperature knob for exploration/exploitation analogous to prior criticality probes |

---
## 3. MVP Scope (In / Out)
| In | Out (Deferred) |
|----|----------------|
| Routing: choose K relays per edge | Store-and-forward keep/drop optimization |
| Persona: 50–128 spin style board | Full inverse-Ising online learning of routing couplings |
| SA solver + geometric schedule | Parallel tempering (PT), quantum annealers |
| Exact-K & diversity penalties | Admission token optimization |
| Telemetry + shadow mode | Hardware acceleration path |

---
## 4. Goals & Non-Goals
Goals:
- ≥10% reduction in p95 latency (zone-cast under churn sim) vs greedy baseline
- ≥X% increase in first-shot doc correctness (persona board pilot)
- Routing solve latency ≤25 ms (median), Persona ≤40 ms
- 100% deterministic audit (seed, schedule, energy trace logged)

Non-Goals:
- Guaranteed global optima
- Specialized hardware requirement
- Full probabilistic calibration of solution distribution

---
## 5. Architecture Overview
Namespace root: `Thunderline.VIM.*`

Core Modules:
- `VIM.Problem` – sparse BQM builder (h, J) + constraint DSL
- `VIM.Solver` – SA + optional tabu polish (flagged)
- `VIM.Metrics` – energy/improvement trace + telemetry emission
- `VIM.CriticalityGate` – variance/susceptibility proxy for adaptive temperature

Adaptors:
- `VIM.RouterAdaptor` – builds problem from relay candidates (rtt, loss, load, zone/rack)
- `VIM.PersonaAdaptor` – builds problem from style toggle priors & co-occurrence

Execution Flow (Routing):
1. Gather cost signals → normalize → h_i
2. Build diversity/overlap penalties → J_ij
3. Add exact-K constraint / capacity
4. SA solve (shadow or active)
5. Telemetry emit + audit log
6. Apply relays if active & no SLA violation

---
## 6. Interfaces
### 6.1 Problem API
```elixir
p = VIM.Problem.new(opts)
|> VIM.Problem.add_spin(id, h)
|> VIM.Problem.add_coupling(i, j, j_ij)
|> VIM.Problem.constraint_exact_k(ids, k, lambda)
|> VIM.Problem.constraint_capacity(ids, weights, cap, lambda)
|> VIM.Problem.constraint_anti_affinity(groups, lambda)
|> VIM.Problem.finalize()
```

### 6.2 Solver
```elixir
VIM.Solver.solve(p, schedule: %{t0: 3.0, alpha: 0.95, iters: 5_000}, seed: s, max_ms: 25)
# => %{bits: %{id => 0|1}, energy: float, energy_initial: float, trace: [...], meta: %{improvement: pct, iterations: n}}
```

### 6.3 Telemetry & Audit
Events:
- `[:vim,:router,:solve,:start|:stop]`
- `[:vim,:persona,:solve,:start|:stop]`
Measurements: `duration_ms`, `energy_initial`, `energy_final`, `improvement_pct`, `iterations`
Metadata: `k`, `n_candidates`, `schedule_id`, `seed`, `mode` (`:shadow|:active`)

Audit Log Record (ETS ring / persisted):
```elixir
%{
  id: uuid_v7(),
  timestamp_ms: now,
  component: :router,
  seed: 12345,
  schedule: %{t0: 3.0, alpha: 0.95, iters: 5000},
  k: 3,
  energy_initial: -12.3,
  energy_final: -15.1,
  improvement_pct: 22.76,
  applied: true,
  fallback: false
}
```

---
## 7. Data Sources
| Domain | Field | Role |
|--------|-------|------|
| TOCP Routing | rtt_ms_p50 / p95 | h normalization input |
| TOCP Routing | packet_loss_pct | h & risk penalty |
| TOCP Routing | relay_queue_depth | overload penalty component |
| Infrastructure | zone / rack tag | J overlap penalty (positive) |
| Infrastructure | historical co-fail count | J coupling input |
| Persona | feature prior weight | h_i baseline |
| Persona | co-occurrence freq | J_ij (sparse) |

---
## 8. Config Surface (Initial)
```elixir
config :thunderline, :vim, %{
  enabled: false,
  shadow_mode: true,
  router: %{k_relays: 3, lambda_exact_k: :auto, schedule: %{t0: 3.0, alpha: 0.95, iters: 5000, max_ms: 25}},
  persona: %{board_size: 128, schedule: %{t0: 2.5, alpha: 0.96, iters: 4000, max_ms: 40}},
  telemetry: %{sample_rate: 1.0},
  temp_ctrl: %{enabled: false, target_variance: 0.05, alpha: 0.05}
}
```

---
## 9. Rollout Plan
| Phase | Mode | Scope | Exit Criteria |
|-------|------|-------|---------------|
| 0 | Shadow | Routing sim only | Stable energy traces, improvement histogram collected |
| 1 | Shadow | Persona board pilot (non-prod) | Feature parity bookkeeping |
| 2 | Active (5%) | Routing | ≥10% p95 latency improvement (sim), SLA stable |
| 3 | Active (select tenants) | Persona | First-shot uplift validated |
| 4 | Expansion | Broader routing/persona | No SLA regressions 2 weeks |

Auto-disable triggers: >2 consecutive solve timeouts ≥max_ms OR p95 latency regression >3% vs baseline.

---
## 10. Success Metrics
| Metric | Target |
|--------|--------|
| routing_p95_latency_improvement | ≥10% |
| persona_first_shot_uplift | ≥X% (TBD) |
| solve_latency_budget_violation_rate | ≤1% |
| fallback_rate | ≤2% |
| audit_log_completeness | ≥99.9% |

---
## 11. Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| Constraint violation (K) | Post-solve repair + adaptive λ scaling |
| Solver latency spikes | Hard timeout + cached greedy fallback |
| Coupling overfit | Sparsify + EMA smoothing + validation gate |
| Privacy leakage (persona) | Hash feature ids, mask raw board dumps by default |
| Route thrash | Dwell time + hysteresis + max Δh per interval |
| Telemetry flood | Sampling + batch aggregation for traces |

---
## 12. Open Questions (Need Answer Before Merge)
1. Final X% target for persona first-shot uplift?  
2. Approve latency budgets (25 ms routing / 40 ms persona)?  
3. Shadow duration minimum (7 days or performance-based)?  
4. Steward assignment (ThunderBolt vs cross-domain working group)?  
5. Audit retention period (N days?).  
6. Accept hashed-only persona feature logging?  

---
## 13. Acceptance Criteria (DIP Approval)
- Feature flag + shadow mode integrated; no behavior change when disabled.  
- Telemetry spec events visible & documented.  
- Simulation harness shows energy improvement distribution.  
- Audit log seeds & schedules reproducible for ≥99.9% solves.  
- Docs updated: Decisions log references DIP, Telemetry lists new vim.* events (planned).  

---
## 14. Implementation Notes
- Store J sparse (ETS + adjacency list).  
- Normalize h to |h_i| ≤ 1.0 before constraint penalties.  
- `lambda_exact_k` auto-scale: λ = factor * mean|h| * K (default factor 2.0).  
- Schedule generation deterministic from seed (derive α jitter if needed).  
- Double-buffer problem versions; atomic swap to avoid half-updated couplings.  
- Provide `vim_cli.exs` script for local what-if solves.  

---
## 15. Future (Not in MVP)
- Parallel tempering / replica exchange.  
- Inverse-Ising online fitting (pseudo-likelihood) for routing J.  
- Store-and-forward keep/drop optimization.  
- Admission credit allocation as coupled spins.  
- GPU SA / digital annealer integration.  

---
## 16. Decision Log
| Date | Actor | Change | Notes |
|------|-------|--------|-------|
| 2025-08-30 | Draft | Initial DIP created | Awaiting steward review |

---
**“If it isn’t auditable, it isn’t adaptive.”**
