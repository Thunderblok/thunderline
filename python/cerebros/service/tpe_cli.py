#!/usr/bin/env python3
"""
TPE CLI - Command-line interface for TPE Bridge.

Called by Thunderline.Thunderbolt.Training.TPEClient via subprocess + JSON.

Usage:
    echo '{"function": "init_study", "args": {...}}' | python tpe_cli.py

Reads a JSON request from stdin, executes the function, and writes JSON to stdout.
"""

import json
import sys
import logging
from typing import Any, Dict

# Configure logging to stderr (not stdout - stdout is for JSON responses)
logging.basicConfig(
    level=logging.INFO,
    format='[%(levelname)s] %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

# Import TPE bridge functions (direct import to avoid __init__.py dependency chain)
try:
    import os
    import importlib.util
    
    # Direct import without going through __init__.py
    _tpe_bridge_path = os.path.join(os.path.dirname(__file__), "tpe_bridge.py")
    _spec = importlib.util.spec_from_file_location("tpe_bridge", _tpe_bridge_path)
    _tpe_bridge = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_tpe_bridge)
    
    # Core functions
    _init_study_raw = _tpe_bridge.init_study
    _suggest_raw = _tpe_bridge.suggest
    _suggest_batch_raw = _tpe_bridge.suggest_batch
    _record_raw = _tpe_bridge.record
    _best_params_raw = _tpe_bridge.best_params
    _get_status_raw = _tpe_bridge.get_status
    _delete_study_raw = _tpe_bridge.delete_study
    _list_studies_raw = _tpe_bridge.list_studies
    OPTUNA_AVAILABLE = _tpe_bridge.OPTUNA_AVAILABLE
    
    # Access the internal cache and helpers
    _studies = _tpe_bridge._studies
    _parse_search_space = _tpe_bridge.parse_search_space
    _suggest_from_space = _tpe_bridge.suggest_from_space
    
    import optuna
    
    def _ensure_study_loaded(study_name: str, storage: str) -> bool:
        """
        Ensure a study is loaded into the process-local cache.
        Returns True if study exists and is loaded, False otherwise.
        """
        if study_name in _studies:
            return True
            
        try:
            # Try to load existing study from storage
            study = optuna.load_study(study_name=study_name, storage=storage)
            
            # Recover search space from user_attrs (stored by init_study)
            search_space = []
            search_space_json = study.user_attrs.get("thunderline_search_space")
            if search_space_json:
                for spec in search_space_json:
                    search_space.append(_tpe_bridge.SearchParam(
                        name=spec["name"],
                        type=spec.get("type", "float"),
                        low=spec.get("low"),
                        high=spec.get("high"),
                        choices=spec.get("choices"),
                        log=spec.get("log", False),
                        step=spec.get("step"),
                    ))
            else:
                # Legacy fallback: infer types from first trial params (if any)
                if len(study.trials) > 0:
                    first_params = study.trials[0].params
                    for name, value in first_params.items():
                        if isinstance(value, float):
                            search_space.append(_tpe_bridge.SearchParam(name=name, type="float", low=0.0, high=1.0))
                        elif isinstance(value, int):
                            search_space.append(_tpe_bridge.SearchParam(name=name, type="int", low=0, high=100))
                        else:
                            search_space.append(_tpe_bridge.SearchParam(name=name, type="categorical", choices=[value]))
            
            _studies[study_name] = {
                "study": study,
                "search_space": search_space,
                "direction": str(study.direction).split(".")[-1].lower(),
            }
            logger.info(f"[TPE CLI] Loaded existing study '{study_name}' with {len(search_space)} params from storage")
            return True
            
        except Exception as e:
            logger.debug(f"[TPE CLI] Could not load study '{study_name}': {e}")
            return False
    
    # Wrapper functions that handle storage
    def init_study(study_name, search_space, seed=None, sampler="TPESampler", 
                   sampler_kwargs=None, direction="maximize", storage=None):
        # Call the original init_study
        result = _init_study_raw(study_name, search_space, seed, sampler, 
                                 sampler_kwargs, direction, storage)
        
        # Store search_space in study user_attrs for recovery later
        if result.get("status") == "ok" and study_name in _studies:
            study = _studies[study_name]["study"]
            # Convert search_space to JSON-serializable format
            search_space_json = [
                {
                    "name": s.get("name") if isinstance(s, dict) else s.name,
                    "type": s.get("type", "float") if isinstance(s, dict) else s.type,
                    "low": s.get("low") if isinstance(s, dict) else s.low,
                    "high": s.get("high") if isinstance(s, dict) else s.high,
                    "choices": s.get("choices") if isinstance(s, dict) else s.choices,
                    "log": s.get("log", False) if isinstance(s, dict) else s.log,
                    "step": s.get("step") if isinstance(s, dict) else s.step,
                }
                for s in (search_space if isinstance(search_space, list) else [])
            ]
            study.set_user_attr("thunderline_search_space", search_space_json)
            logger.info(f"[TPE CLI] Stored search_space in study user_attrs")
        
        return result
    
    def suggest(study_name, storage=None):
        if not _ensure_study_loaded(study_name, storage):
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        return _suggest_raw(study_name)
    
    def suggest_batch(study_name, n=1, storage=None):
        if not _ensure_study_loaded(study_name, storage):
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        return _suggest_batch_raw(study_name, n)
    
    def record(study_name, params, value, trial_id=None, state="complete", storage=None):
        if not _ensure_study_loaded(study_name, storage):
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        return _record_raw(study_name, params, value, trial_id, state)
    
    def best_params(study_name, storage=None):
        if not _ensure_study_loaded(study_name, storage):
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        return _best_params_raw(study_name)
    
    def get_status(study_name, storage=None):
        if not _ensure_study_loaded(study_name, storage):
            return {"status": "error", "reason": f"study '{study_name}' not found"}
        return _get_status_raw(study_name)
    
    def delete_study(study_name, storage=None):
        try:
            optuna.delete_study(study_name=study_name, storage=storage)
            if study_name in _studies:
                del _studies[study_name]
            return {"status": "ok", "study_name": study_name}
        except Exception as e:
            return {"status": "error", "reason": str(e)}
    
    def list_studies(storage=None):
        try:
            summaries = optuna.get_all_study_summaries(storage=storage)
            return {
                "status": "ok",
                "studies": [
                    {
                        "name": s.study_name,
                        "n_trials": s.n_trials,
                        "direction": str(s.direction).split(".")[-1].lower() if s.direction else None,
                    }
                    for s in summaries
                ]
            }
        except Exception as e:
            return {"status": "error", "reason": str(e)}
    
except Exception as e:
    logger.warning(f"Failed to import tpe_bridge: {e}")
    OPTUNA_AVAILABLE = False
    
    # Define stub functions
    def init_study(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def suggest(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def suggest_batch(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def record(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def best_params(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def get_status(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def delete_study(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}
    
    def list_studies(*args, **kwargs):
        return {"status": "error", "reason": "tpe_bridge not available"}


def ping() -> Dict[str, Any]:
    """Health check endpoint."""
    return {
        "status": "ok",
        "optuna_available": OPTUNA_AVAILABLE,
    }


FUNCTION_MAP = {
    "init_study": init_study,
    "suggest": suggest,
    "suggest_batch": suggest_batch,
    "record": record,
    "best_params": best_params,
    "get_status": get_status,
    "delete_study": delete_study,
    "list_studies": list_studies,
    "ping": ping,
}


def get_default_storage() -> str:
    """Get default SQLite storage path."""
    # Store in priv/tpe_studies/ for persistence
    base_dir = os.path.join(os.path.dirname(__file__), "..", "..", "..", "priv", "tpe_studies")
    os.makedirs(base_dir, exist_ok=True)
    return f"sqlite:///{os.path.join(base_dir, 'optuna_studies.db')}"


def handle_request(request: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle a single JSON request.
    
    Args:
        request: {"function": str, "args": dict}
        
    Returns:
        Result dictionary
    """
    function_name = request.get("function")
    args = request.get("args", {})
    
    if function_name not in FUNCTION_MAP:
        return {"status": "error", "reason": f"unknown function: {function_name}"}
    
    func = FUNCTION_MAP[function_name]
    
    # Get storage path (default to SQLite for persistence between CLI calls)
    storage = args.get("storage") or get_default_storage()
    
    try:
        # Handle different function signatures
        if function_name == "init_study":
            return func(
                study_name=args.get("study_name"),
                search_space=args.get("search_space", []),
                seed=args.get("seed"),
                sampler=args.get("sampler", "TPESampler"),
                sampler_kwargs=args.get("sampler_kwargs"),
                direction=args.get("direction", "maximize"),
                storage=storage,
            )
        
        elif function_name == "suggest":
            return func(study_name=args.get("study_name"), storage=storage)
        
        elif function_name == "suggest_batch":
            return func(
                study_name=args.get("study_name"),
                n=args.get("n", 1),
                storage=storage,
            )
        
        elif function_name == "record":
            return func(
                study_name=args.get("study_name"),
                params=args.get("params", {}),
                value=args.get("value", 0.0),
                trial_id=args.get("trial_id"),
                state=args.get("state", "complete"),
                storage=storage,
            )
        
        elif function_name == "best_params":
            return func(study_name=args.get("study_name"), storage=storage)
        
        elif function_name == "get_status":
            return func(study_name=args.get("study_name"), storage=storage)
        
        elif function_name == "delete_study":
            return func(study_name=args.get("study_name"), storage=storage)
        
        elif function_name == "list_studies":
            return func(storage=storage)
        
        elif function_name == "ping":
            return func()
        
        else:
            return {"status": "error", "reason": f"unhandled function: {function_name}"}
    
    except Exception as e:
        logger.exception(f"Error handling {function_name}")
        return {"status": "error", "reason": str(e)}


def main():
    """Main entry point - read from stdin, write to stdout."""
    try:
        # Read request from stdin
        line = sys.stdin.readline().strip()
        
        if not line:
            result = {"status": "error", "reason": "empty input"}
        else:
            request = json.loads(line)
            result = handle_request(request)
        
        # Write result to stdout
        print(json.dumps(result))
        sys.exit(0)
        
    except json.JSONDecodeError as e:
        print(json.dumps({"status": "error", "reason": f"invalid JSON: {e}"}))
        sys.exit(0)  # Exit 0 so Elixir doesn't treat as crash
        
    except Exception as e:
        logger.exception("Unexpected error")
        print(json.dumps({"status": "error", "reason": str(e)}))
        sys.exit(0)


if __name__ == "__main__":
    main()
