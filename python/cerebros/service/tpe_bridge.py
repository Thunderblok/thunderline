"""
TPE Bridge - Optuna-based Tree-structured Parzen Estimator for Elixir↔Python interop.

This module provides a bridge between Thunderline's Elixir TPEBridge GenServer and
Optuna's TPESampler for Bayesian hyperparameter optimization.

HC-41: Python TPE Scaffold for Cerebros-DiffLogic Integration.

Usage from Elixir (via Snex):
    # Initialize study
    tpe_bridge.init_study(
        study_name="ca_edge_of_chaos",
        search_space=[
            {"name": "lambda", "type": "float", "low": 0.0, "high": 1.0},
            {"name": "bias", "type": "float", "low": 0.0, "high": 1.0},
        ],
        seed=42
    )
    
    # Suggest parameters
    params = tpe_bridge.suggest(study_name="ca_edge_of_chaos")
    
    # Record trial result
    tpe_bridge.record(study_name="ca_edge_of_chaos", params=params, value=0.85)
    
    # Get best parameters
    best = tpe_bridge.best_params(study_name="ca_edge_of_chaos")

References:
- Optuna TPESampler: https://optuna.readthedocs.io/en/stable/reference/samplers.html
- HC-41: Python TPE Scaffold
- HC-40: CA.Criticality metrics for edge-of-chaos optimization
"""

import json
import logging
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Union
from enum import Enum

try:
    import optuna
    from optuna.samplers import TPESampler
    OPTUNA_AVAILABLE = True
except ImportError:
    OPTUNA_AVAILABLE = False
    optuna = None

logger = logging.getLogger(__name__)


# =============================================================================
# STUDY STORAGE
# =============================================================================

# In-memory study storage (process-local)
# Key: study_name -> {"study": optuna.Study, "search_space": List[Dict]}
_studies: Dict[str, Dict[str, Any]] = {}


# =============================================================================
# SEARCH SPACE HELPERS
# =============================================================================

@dataclass
class SearchParam:
    """A single search parameter specification."""
    name: str
    type: str  # "float", "int", "categorical"
    low: Optional[float] = None
    high: Optional[float] = None
    choices: Optional[List[Any]] = None
    log: bool = False
    step: Optional[Union[int, float]] = None


def parse_search_space(raw_space: List[Dict[str, Any]]) -> List[SearchParam]:
    """
    Parse search space from Elixir-serialized format.
    
    Args:
        raw_space: List of dicts with keys: name, type, low, high, choices, log, step
        
    Returns:
        List of SearchParam objects
    """
    params = []
    for spec in raw_space:
        param = SearchParam(
            name=spec["name"],
            type=spec.get("type", "float"),
            low=spec.get("low"),
            high=spec.get("high"),
            choices=spec.get("choices"),
            log=spec.get("log", False),
            step=spec.get("step"),
        )
        params.append(param)
    return params


def suggest_from_space(trial: "optuna.Trial", search_space: List[SearchParam]) -> Dict[str, Any]:
    """
    Suggest parameters from a parsed search space.
    
    Args:
        trial: Optuna trial object
        search_space: List of SearchParam specifications
        
    Returns:
        Dictionary of suggested parameter values
    """
    params = {}
    for spec in search_space:
        if spec.type == "float":
            params[spec.name] = trial.suggest_float(
                spec.name,
                spec.low,
                spec.high,
                log=spec.log,
                step=spec.step,
            )
        elif spec.type == "int":
            params[spec.name] = trial.suggest_int(
                spec.name,
                int(spec.low),
                int(spec.high),
                step=int(spec.step) if spec.step else 1,
                log=spec.log,
            )
        elif spec.type == "categorical":
            params[spec.name] = trial.suggest_categorical(
                spec.name,
                spec.choices,
            )
        else:
            logger.warning(f"Unknown param type '{spec.type}' for '{spec.name}', using float")
            params[spec.name] = trial.suggest_float(spec.name, spec.low, spec.high)
    
    return params


# =============================================================================
# PUBLIC API (Called from Elixir via Snex)
# =============================================================================

def init_study(
    study_name: str,
    search_space: List[Dict[str, Any]],
    seed: Optional[int] = None,
    sampler: str = "TPESampler",
    sampler_kwargs: Optional[Dict[str, Any]] = None,
    direction: str = "maximize",
    storage: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Initialize an Optuna study with TPE sampler.
    
    Args:
        study_name: Unique name for the study
        search_space: List of parameter specifications
        seed: Random seed for reproducibility
        sampler: Sampler class name (default: TPESampler)
        sampler_kwargs: Additional sampler arguments
        direction: Optimization direction ("maximize" or "minimize")
        storage: Optional SQLite/PostgreSQL storage URL
        
    Returns:
        {"status": "ok", "study_name": str, "n_params": int}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        # Parse search space
        parsed_space = parse_search_space(search_space)
        
        # Configure sampler
        sampler_kwargs = sampler_kwargs or {}
        if seed is not None:
            sampler_kwargs["seed"] = seed
        
        # Default TPE settings for multivariate optimization
        if sampler == "TPESampler":
            sampler_kwargs.setdefault("multivariate", True)
            sampler_kwargs.setdefault("n_startup_trials", 10)
            sampler_kwargs.setdefault("constant_liar", True)  # Better for parallel
            sampler_obj = TPESampler(**sampler_kwargs)
        else:
            # Fallback to random sampler
            sampler_obj = optuna.samplers.RandomSampler(seed=seed)
        
        # Create or load study
        study = optuna.create_study(
            study_name=study_name,
            sampler=sampler_obj,
            direction=direction,
            storage=storage,
            load_if_exists=True,
        )
        
        # Store in process-local cache
        _studies[study_name] = {
            "study": study,
            "search_space": parsed_space,
            "direction": direction,
        }
        
        logger.info(f"[TPEBridge] Initialized study '{study_name}' with {len(parsed_space)} params")
        
        return {
            "status": "ok",
            "study_name": study_name,
            "n_params": len(parsed_space),
            "direction": direction,
            "sampler": sampler,
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] init_study failed: {e}")
        return {"status": "error", "reason": str(e)}


def suggest(study_name: str) -> Dict[str, Any]:
    """
    Suggest the next set of parameters to evaluate.
    
    Uses TPE (Tree-structured Parzen Estimator) to suggest parameters
    that are likely to improve the objective.
    
    Args:
        study_name: Name of the study
        
    Returns:
        {"status": "ok", "params": Dict, "trial_id": int} or
        {"status": "error", "reason": str}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        if study_name not in _studies:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        
        study_data = _studies[study_name]
        study = study_data["study"]
        search_space = study_data["search_space"]
        
        # Create a new trial
        trial = study.ask()
        
        # Suggest parameters based on search space
        params = suggest_from_space(trial, search_space)
        
        logger.debug(f"[TPEBridge] Suggested trial {trial.number}: {params}")
        
        return {
            "status": "ok",
            "params": params,
            "trial_id": trial.number,
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] suggest failed: {e}")
        return {"status": "error", "reason": str(e)}


def record(
    study_name: str,
    params: Dict[str, Any],
    value: float,
    trial_id: Optional[int] = None,
    state: str = "complete",
) -> Dict[str, Any]:
    """
    Record the result of evaluating a parameter set.
    
    Args:
        study_name: Name of the study
        params: The parameter values that were evaluated
        value: The objective value (fitness/loss)
        trial_id: Optional trial ID (for async workflows)
        state: Trial state ("complete", "pruned", "fail")
        
    Returns:
        {"status": "ok", "trial_id": int, "is_best": bool}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        if study_name not in _studies:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        
        study_data = _studies[study_name]
        study = study_data["study"]
        direction = study_data["direction"]
        
        # Map state to Optuna trial state
        state_map = {
            "complete": optuna.trial.TrialState.COMPLETE,
            "pruned": optuna.trial.TrialState.PRUNED,
            "fail": optuna.trial.TrialState.FAIL,
        }
        trial_state = state_map.get(state, optuna.trial.TrialState.COMPLETE)
        
        # Find or get trial
        if trial_id is not None:
            # Tell the study about this trial's result
            study.tell(trial_id, value, state=trial_state)
            used_trial_id = trial_id
        else:
            # Add a completed trial manually (for external evaluations)
            study.add_trial(
                optuna.trial.create_trial(
                    params=params,
                    values=[value],
                    state=trial_state,
                )
            )
            used_trial_id = len(study.trials) - 1
        
        # Check if this is the best trial
        is_best = False
        if study.best_trial is not None:
            best_value = study.best_trial.value
            if direction == "maximize":
                is_best = value >= best_value
            else:
                is_best = value <= best_value
        
        logger.debug(f"[TPEBridge] Recorded trial {used_trial_id}: value={value}, is_best={is_best}")
        
        return {
            "status": "ok",
            "trial_id": used_trial_id,
            "is_best": is_best,
            "n_complete": len([t for t in study.trials if t.state == optuna.trial.TrialState.COMPLETE]),
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] record failed: {e}")
        return {"status": "error", "reason": str(e)}


def best_params(study_name: str) -> Dict[str, Any]:
    """
    Get the best parameters found so far.
    
    Args:
        study_name: Name of the study
        
    Returns:
        {"status": "ok", "params": Dict, "value": float, "trial_id": int} or
        {"status": "error", "reason": str}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        if study_name not in _studies:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        
        study = _studies[study_name]["study"]
        
        if study.best_trial is None:
            return {"status": "error", "reason": "no completed trials"}
        
        best = study.best_trial
        
        return {
            "status": "ok",
            "params": best.params,
            "value": best.value,
            "trial_id": best.number,
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] best_params failed: {e}")
        return {"status": "error", "reason": str(e)}


def get_status(study_name: str) -> Dict[str, Any]:
    """
    Get current study status.
    
    Args:
        study_name: Name of the study
        
    Returns:
        {"status": "ok", "n_trials": int, "n_complete": int, "best_value": float, ...}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        if study_name not in _studies:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        
        study_data = _studies[study_name]
        study = study_data["study"]
        
        complete_trials = [t for t in study.trials if t.state == optuna.trial.TrialState.COMPLETE]
        
        best_value = None
        best_params = None
        if study.best_trial is not None:
            best_value = study.best_trial.value
            best_params = study.best_trial.params
        
        return {
            "status": "ok",
            "study_name": study_name,
            "n_trials": len(study.trials),
            "n_complete": len(complete_trials),
            "direction": study_data["direction"],
            "best_value": best_value,
            "best_params": best_params,
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] get_status failed: {e}")
        return {"status": "error", "reason": str(e)}


def delete_study(study_name: str) -> Dict[str, Any]:
    """
    Delete a study from memory.
    
    Args:
        study_name: Name of the study to delete
        
    Returns:
        {"status": "ok"} or {"status": "error", "reason": str}
    """
    try:
        if study_name in _studies:
            del _studies[study_name]
            logger.info(f"[TPEBridge] Deleted study '{study_name}'")
            return {"status": "ok"}
        else:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
            
    except Exception as e:
        logger.error(f"[TPEBridge] delete_study failed: {e}")
        return {"status": "error", "reason": str(e)}


def list_studies() -> Dict[str, Any]:
    """
    List all active studies.
    
    Returns:
        {"status": "ok", "studies": List[str]}
    """
    return {
        "status": "ok",
        "studies": list(_studies.keys()),
        "count": len(_studies),
    }


# =============================================================================
# BATCH API (for efficient multi-trial operations)
# =============================================================================

def suggest_batch(study_name: str, n: int = 1) -> Dict[str, Any]:
    """
    Suggest multiple parameter sets at once (for parallel evaluation).
    
    Args:
        study_name: Name of the study
        n: Number of parameter sets to suggest
        
    Returns:
        {"status": "ok", "trials": List[{"params": Dict, "trial_id": int}]}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        if study_name not in _studies:
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        
        study_data = _studies[study_name]
        study = study_data["study"]
        search_space = study_data["search_space"]
        
        trials = []
        for _ in range(n):
            trial = study.ask()
            params = suggest_from_space(trial, search_space)
            trials.append({
                "params": params,
                "trial_id": trial.number,
            })
        
        logger.debug(f"[TPEBridge] Suggested batch of {n} trials")
        
        return {
            "status": "ok",
            "trials": trials,
            "count": len(trials),
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] suggest_batch failed: {e}")
        return {"status": "error", "reason": str(e)}


def record_batch(
    study_name: str,
    results: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """
    Record multiple trial results at once.
    
    Args:
        study_name: Name of the study
        results: List of {"trial_id": int, "value": float, "state": str}
        
    Returns:
        {"status": "ok", "recorded": int}
    """
    if not OPTUNA_AVAILABLE:
        return {"status": "error", "reason": "optuna not installed"}
    
    try:
        recorded = 0
        errors = []
        
        for result in results:
            resp = record(
                study_name=study_name,
                params=result.get("params", {}),
                value=result["value"],
                trial_id=result.get("trial_id"),
                state=result.get("state", "complete"),
            )
            if resp["status"] == "ok":
                recorded += 1
            else:
                errors.append(resp.get("reason", "unknown error"))
        
        return {
            "status": "ok" if not errors else "partial",
            "recorded": recorded,
            "errors": errors if errors else None,
        }
        
    except Exception as e:
        logger.error(f"[TPEBridge] record_batch failed: {e}")
        return {"status": "error", "reason": str(e)}


# =============================================================================
# PRESET SEARCH SPACES (for DiffLogic CA optimization)
# =============================================================================

def get_ca_search_space() -> List[Dict[str, Any]]:
    """
    Get the default search space for DiffLogic CA edge-of-chaos optimization.
    
    Returns parameters tuned for criticality metrics:
    - lambda: Lyapunov exponent target
    - bias: CA state bias
    - gate_temp: DiffLogic gate temperature
    - diffusion_rate: Spatial diffusion coefficient
    """
    return [
        {"name": "lambda", "type": "float", "low": 0.0, "high": 1.0},
        {"name": "bias", "type": "float", "low": 0.0, "high": 1.0},
        {"name": "gate_temp", "type": "float", "low": 0.1, "high": 2.0},
        {"name": "diffusion_rate", "type": "float", "low": 0.0, "high": 0.5},
    ]


def get_criticality_search_space() -> List[Dict[str, Any]]:
    """
    Extended search space including edge-of-chaos criticality parameters.
    
    Includes parameters for:
    - Core CA dynamics (lambda, bias, gate_temp, diffusion)
    - PLV (Phase Locking Value) targeting
    - Entropy bounds
    - Lyapunov exponent control
    """
    return [
        # Core CA parameters
        {"name": "lambda", "type": "float", "low": 0.0, "high": 1.0},
        {"name": "bias", "type": "float", "low": 0.0, "high": 1.0},
        {"name": "gate_temp", "type": "float", "low": 0.1, "high": 2.0},
        {"name": "diffusion_rate", "type": "float", "low": 0.0, "high": 0.5},
        
        # Criticality targets
        {"name": "plv_target", "type": "float", "low": 0.3, "high": 0.7},
        {"name": "entropy_target", "type": "float", "low": 0.4, "high": 0.9},
        {"name": "lyapunov_target", "type": "float", "low": -0.1, "high": 0.1, "log": False},
        
        # Architecture parameters
        {"name": "lattice_size", "type": "int", "low": 16, "high": 128, "step": 16},
        {"name": "neighborhood_radius", "type": "int", "low": 1, "high": 5},
    ]


# =============================================================================
# CLI ENTRY POINT (for testing)
# =============================================================================

def main():
    """CLI entry point for testing TPE bridge."""
    import argparse
    
    parser = argparse.ArgumentParser(description="TPE Bridge CLI")
    parser.add_argument("--action", choices=["init", "suggest", "record", "best", "status"],
                       required=True, help="Action to perform")
    parser.add_argument("--study", default="test_study", help="Study name")
    parser.add_argument("--value", type=float, help="Value to record")
    parser.add_argument("--n-trials", type=int, default=5, help="Number of trials to run")
    
    args = parser.parse_args()
    
    logging.basicConfig(level=logging.DEBUG)
    
    if args.action == "init":
        result = init_study(
            study_name=args.study,
            search_space=get_ca_search_space(),
            seed=42,
        )
        print(json.dumps(result, indent=2))
        
    elif args.action == "suggest":
        result = suggest(args.study)
        print(json.dumps(result, indent=2))
        
    elif args.action == "record":
        if args.value is None:
            print("Error: --value required for record action")
            return
        result = record(args.study, {}, args.value)
        print(json.dumps(result, indent=2))
        
    elif args.action == "best":
        result = best_params(args.study)
        print(json.dumps(result, indent=2))
        
    elif args.action == "status":
        result = get_status(args.study)
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
