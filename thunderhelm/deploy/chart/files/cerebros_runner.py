#!/usr/bin/env python3
"""Thunderline demo Cerebros runner service.

Exposes lightweight HTTP endpoints used by Thunderline Livebook and the
Cerebros bridge stub. Provides random-search proposals, a mock trainer that
logs metrics to MLflow, and simple bookkeeping for run/trial lifecycle events.
"""

from __future__ import annotations

import math
import os
import random
import time
from typing import Any, Dict, List, Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field

try:
    import mlflow  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    mlflow = None  # type: ignore

app = FastAPI(title="Thunderline Cerebros Runner", version="0.1.0")

RUNS: Dict[str, Dict[str, Any]] = {}

MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI")
MLFLOW_EXPERIMENT = os.getenv("MLFLOW_EXPERIMENT_NAME", "thunderline-cerebros-demo")

if mlflow and MLFLOW_TRACKING_URI:
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    try:
        mlflow.set_experiment(MLFLOW_EXPERIMENT)
    except Exception:
        mlflow.create_experiment(MLFLOW_EXPERIMENT)
        mlflow.set_experiment(MLFLOW_EXPERIMENT)


# ---------------------------------------------------------------------------
# Request models


class SearchSpace(BaseModel):
    __root__: Dict[str, Dict[str, List[float] | List[str]]]

    def sample(self) -> Dict[str, Any]:
        params: Dict[str, Any] = {}

        for name, spec in self.__root__.items():
            if "choice" in spec:
                params[name] = random.choice(spec["choice"])  # type: ignore[arg-type]
            elif "uniform" in spec:
                low, high = spec["uniform"]  # type: ignore[assignment]
                params[name] = random.uniform(float(low), float(high))
            elif "loguniform" in spec:
                low, high = map(float, spec["loguniform"])  # type: ignore[arg-type]
                params[name] = math.exp(random.uniform(math.log(low), math.log(high)))
            else:
                params[name] = None

        return params


class ProposeRequest(BaseModel):
    run_id: str
    k: int = Field(gt=0, le=64)
    space: SearchSpace


class TrainRequest(BaseModel):
    trial_id: str
    params: Dict[str, Any]
    dataset: Optional[List[Any]] = None


class BridgeRequest(BaseModel):
    run_id: str
    payload: Dict[str, Any] = Field(default_factory=dict)


class BridgeTrialRequest(BridgeRequest):
    trial_id: str
    metrics: Dict[str, Any] = Field(default_factory=dict)
    parameters: Dict[str, Any] = Field(default_factory=dict)
    status: str = "succeeded"


# ---------------------------------------------------------------------------
# Helpers


def _flatten(prefix: str, data: Dict[str, Any], acc: Dict[str, Any]) -> None:
    for key, value in data.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            _flatten(path, value, acc)
        else:
            acc[path] = value


def flatten_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    acc: Dict[str, Any] = {}
    _flatten("", data, acc)
    return acc


def log_to_mlflow(trial_id: str, params: Dict[str, Any], metrics: Dict[str, Any]) -> None:
    if not mlflow:
        return

    flat_params = flatten_dict(params)

    with mlflow.start_run(run_name=trial_id) as run:  # type: ignore[attr-defined]
        run_id = run.info.run_id
        mlflow.log_params(flat_params)
        metric_payload = {k: float(v) for k, v in metrics.items() if isinstance(v, (int, float))}
        if metric_payload:
            mlflow.log_metrics(metric_payload)
        mlflow.set_tag("trial_id", trial_id)
        mlflow.set_tag("timestamp", str(time.time()))
        RUNS.setdefault(trial_id, {})["mlflow_run_id"] = run_id


def generate_metrics(params: Dict[str, Any]) -> Dict[str, float]:
    head = params.get("head", "kgam")
    base_acc = 0.86 if head == "irope" else 0.80
    base_lat = 58.0 if head == "irope" else 34.0

    smooth = float(params.get("controller.smooth", 0.2))
    bw = float(params.get("curation.kernel_bw", 0.5))
    lr = float(params.get("lr", 1.0e-3))

    latency = base_lat - 10.0 * smooth + 6.0 * (bw - 0.5) + (random.random() - 0.5) * 4.0
    accuracy = (
        base_acc
        + 0.04 * math.exp(-abs(bw - 0.4))
        - 0.03 * smooth
        + 0.2 * math.log10(max(1.0e-6, 1.0e-2 / lr))
        + (random.random() - 0.5) * 0.01
    )
    energy = 1.8 + 0.02 * latency + (random.random() - 0.5) * 0.1

    return {
        "accuracy": round(accuracy, 4),
        "latency_ms": round(latency, 2),
        "energy_j": round(energy, 3),
        "artifact_bytes": 96_000 + int(random.random() * 16_000),
    }


# ---------------------------------------------------------------------------
# Endpoints


@app.post("/propose")
def propose(req: ProposeRequest) -> List[Dict[str, Any]]:
    RUNS.setdefault(req.run_id, {"trials": []})
    proposals = []

    for rank in range(req.k):
        params = req.space.sample()
        score = {"l": random.random(), "g": random.random()}
        proposals.append({"params": params, "score": score, "rank": rank + 1})

    return proposals


@app.post("/train")
def train(req: TrainRequest) -> Dict[str, Any]:
    metrics = generate_metrics(req.params)
    log_to_mlflow(req.trial_id, req.params, metrics)

    RUNS.setdefault(req.trial_id, {})["metrics"] = metrics
    return {
        "trial_id": req.trial_id,
        "metrics": metrics,
        "dataset_size": len(req.dataset or []),
    }


@app.post("/bridge/start")
def bridge_start(req: BridgeRequest) -> Dict[str, Any]:
    RUNS.setdefault(req.run_id, {"events": []})
    RUNS[req.run_id]["started_at"] = time.time()
    RUNS[req.run_id]["events"].append({"op": "start", "payload": req.payload})
    return {"run_id": req.run_id, "status": "started"}


@app.post("/bridge/record")
def bridge_record(req: BridgeTrialRequest) -> Dict[str, Any]:
    RUNS.setdefault(req.run_id, {"events": []})
    trial_info = {
        "trial_id": req.trial_id,
        "metrics": req.metrics,
        "parameters": req.parameters,
        "status": req.status,
    }
    RUNS[req.run_id].setdefault("trials", []).append(trial_info)
    RUNS[req.run_id]["events"].append({"op": "record", "trial": trial_info})
    log_to_mlflow(req.trial_id, req.parameters, req.metrics)
    return {"run_id": req.run_id, "trial": req.trial_id, "status": req.status}


@app.post("/bridge/finalize")
def bridge_finalize(req: BridgeRequest) -> Dict[str, Any]:
    run = RUNS.setdefault(req.run_id, {"events": []})
    run["events"].append({"op": "finalize", "payload": req.payload})
    trials = run.get("trials", [])

    if trials:
        best = max(trials, key=lambda item: item["metrics"].get("accuracy", 0.0))
    else:
        best = None

    summary = {
        "run_id": req.run_id,
        "duration_ms": int((time.time() - run.get("started_at", time.time())) * 1000),
        "trials": len(trials),
        "best_trial": best,
    }

    return summary


@app.get("/healthz")
def health() -> Dict[str, str]:
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn  # type: ignore

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8088")))
