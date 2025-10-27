# Thunderline Numerics Scaffold

## Adapters

- ElixirFallback (default)
- Sidecar (HTTP FastAPI at THUNDERLINE_NUMERICS_SIDECAR_URL)
- NIF (Rustler skeleton)

## Quickstart

1. Deps

- mix deps.get

1. Run demo

- mix numerics.gemm_demo

1. Benchmark (optional)

- mix run bench/gemm_bench.exs

## Sidecar

- python -m venv .venv && source .venv/bin/activate
- pip install -r sidecar/requirements.txt
- python sidecar/cerebros_sidecar.py

## Switch adapter

In `config/config.exs` set `:thunderline, :numerics_adapter` to one of:

- Thunderline.Thunderbolt.Numerics.Adapters.ElixirFallback
- Thunderline.Thunderbolt.Numerics.Adapters.Sidecar
- Thunderline.Thunderbolt.Numerics.Adapters.NIF (stub)
