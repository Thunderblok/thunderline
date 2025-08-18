% ADR-001: Constants Policy (Ring 0)

Status: Accepted  
Date: 2025-08-18  
Drivers: Fast fanout reads, safety, observability, avoiding misuse of `:persistent_term`.

## Decision
Introduce `Thunderline.Const` as the single gate for a *curated* set of global, read‑mostly constants (Ring 0). Implementation uses `:persistent_term` for zero‑copy reads. Writes are limited to boot (put_once/3) or explicit, audited swaps (swap!/3). All mutable shared state remains in ETS (Ring 1) or Postgres (Ring 2).

## Allowed Keys (Initial Set)
* `{:grid, :region_index}` – region_id => integer index map
* `{:automata, :offsets, r}` – neighborhood offsets for radius r
* `{:rules, :ca, :version}` – active CA rule struct
* `{:rules, :ising, :default}` – default Ising param struct (caps, beta)
* `{:ml, :vocab, name}` – model vocabulary manifests

New keys require PR updating this ADR.

## Exclusions
Do NOT store: wait_curve, contact_threshold, quotas, pheromones, logits, counters – these change often → ETS.

## Rationale
* `:persistent_term` gives constant‑time, zero‑copy reads (better for large static maps)
* Strict gate prevents uncontrolled sprawl / silent memory spikes
* Telemetry provides audit trail & sizing visibility

## Telemetry
Events:
* `[:thunderline, :const, :put_once]`
* `[:thunderline, :const, :swap]`

Measurements: `%{size_bytes: integer}`  
Metadata: `%{key: term, reason?, who?, version?}`

## Migration Plan
1. Add module & ADR (this change)
2. Load region_index & offsets at boot
3. Move CA rule + Ising params
4. Dashboards for size + swap frequency
5. Bench read/write under `bench/`

## Alternatives
fastglobal (extra dep, less explicit), ETS only (heap copy), application env (no runtime swap/telemetry).

## Rollback
Replace fetches with ETS or module attributes; remove `Thunderline.Const` – low risk.
