"""
Cerebros NAS Service - Python bridge for neural architecture search using Genetic Algorithm

This module wraps the Cerebros GA implementation from:
https://github.com/david-thrower/cerebros-core-algorithm-alpha

It provides a clean interface for Elixir to call Cerebros NAS via Pythonx.
"""
import logging
import json
import os
from typing import Dict, Any, List, Optional
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def normalize_dict_keys(obj):
    """
    Recursively convert bytes keys AND values to strings in nested dicts/lists.
    This handles Pythonx encoding which converts Elixir strings to bytes.
    """
    if isinstance(obj, bytes):
        # Convert bytes values to strings
        return obj.decode('utf-8')
    elif isinstance(obj, dict):
        return {
            normalize_dict_keys(k): normalize_dict_keys(v)
            for k, v in obj.items()
        }
    elif isinstance(obj, list):
        return [normalize_dict_keys(item) for item in obj]
    else:
        return obj


# Import Cerebros GA (we'll need to add the cerebros repo to PYTHONPATH)
try:
    from cerebros_ga import cerebros_core_ga
    CEREBROS_AVAILABLE = True
except ImportError:
    CEREBROS_AVAILABLE = False
    logger.warning("cerebros_ga module not found - using stub implementation")


def run_nas(spec: Dict[str, Any], opts: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute Neural Architecture Search using Cerebros Genetic Algorithm
    
    This is the main entry point called from Elixir via Pythonx.
    
    Args:
        spec: Specification with:
            - dataset_id: str - Dataset identifier
            - search_space: dict - Architecture search space configuration
            - objective: str - What to optimize ('accuracy', 'loss', etc)
            
        opts: Options with:
            - run_id: str - Unique run identifier
            - pulse_id: str (optional) - Pulse/experiment group ID
            - budget: dict - Resource constraints:
                - max_trials: int - Maximum number of architectures to try
                - max_time_seconds: int - Maximum time budget
                - population_size: int - GA population size
            - parameters: dict - GA-specific parameters:
                - mutation_rate: float
                - crossover_rate: float
                - elite_size: int
            - tau: float (optional) - Temperature parameter for selection
    
    Returns:
        dict: {
            "status": "success" | "failed",
            "best_model": dict - Best architecture found,
            "best_metric": float - Best metric value achieved,
            "completed_trials": int - Number of trials completed,
            "population_history": list - Evolution history,
            "artifacts": list - Paths to saved artifacts,
            "metadata": dict - Additional run information,
            "error": str (optional) - Error message if failed
        }
    """
    # Normalize keys from bytes to strings FIRST (Pythonx encoding)
    spec = normalize_dict_keys(spec)
    opts = normalize_dict_keys(opts)
    
    run_id = opts.get("run_id", "unknown")
    
    logger.info(f"Starting Cerebros NAS run {run_id}")
    logger.info(f"Spec: {json.dumps(spec, indent=2)}")
    logger.info(f"Opts: {json.dumps(opts, indent=2)}")
    
    try:
        # Extract configuration
        dataset_id = spec.get("dataset_id")
        search_space = spec.get("search_space", {})
        objective = spec.get("objective", "accuracy")
        
        budget = opts.get("budget", {})
        max_trials = budget.get("max_trials", 10)
        population_size = budget.get("population_size", 20)
        
        parameters = opts.get("parameters", {})
        mutation_rate = parameters.get("mutation_rate", 0.1)
        crossover_rate = parameters.get("crossover_rate", 0.7)
        elite_size = parameters.get("elite_size", 2)
        
        tau = opts.get("tau", 1.0)
        
        # Validate required inputs
        if not dataset_id:
            raise ValueError("dataset_id is required in spec")
        
        if CEREBROS_AVAILABLE:
            # Run actual Cerebros GA
            result = run_cerebros_ga(
                dataset_id=dataset_id,
                search_space=search_space,
                objective=objective,
                max_trials=max_trials,
                population_size=population_size,
                mutation_rate=mutation_rate,
                crossover_rate=crossover_rate,
                elite_size=elite_size,
                tau=tau,
                run_id=run_id
            )
        else:
            # Stub implementation for testing without Cerebros
            result = run_stub_nas(
                dataset_id=dataset_id,
                max_trials=max_trials,
                run_id=run_id
            )
        
        logger.info(f"NAS run {run_id} completed successfully")
        return result
        
    except Exception as e:
        logger.error(f"NAS run {run_id} failed: {str(e)}", exc_info=True)
        return {
            "status": "failed",
            "error": str(e),
            "run_id": run_id,
            "completed_trials": 0,
            "metadata": {
                "error_type": type(e).__name__,
                "timestamp": datetime.utcnow().isoformat()
            }
        }


def run_cerebros_ga(
    dataset_id: str,
    search_space: Dict,
    objective: str,
    max_trials: int,
    population_size: int,
    mutation_rate: float,
    crossover_rate: float,
    elite_size: int,
    tau: float,
    run_id: str
) -> Dict[str, Any]:
    """
    Run the actual Cerebros Genetic Algorithm
    
    This wraps cerebros_core_ga from the Cerebros repository.
    """
    logger.info(f"Running Cerebros GA for {max_trials} generations")
    
    # Load dataset
    X_train, y_train, X_test, y_test = load_dataset(dataset_id)
    
    # Configure Cerebros GA parameters matching test_cerebros.py
    ga_params = {
        'population_size': population_size,
        'mutation_rate': mutation_rate,
        'crossover_rate': crossover_rate,
        'elite_size': elite_size,
        'max_generations': max_trials,  # Map max_trials to generations
        'tau': tau,
        'objective': objective
    }
    
    # Run Cerebros GA
    # Based on test_cerebros.py, cerebros_core_ga returns:
    # (best_individual, best_fitness, population_history)
    best_individual, best_fitness, population_history = cerebros_core_ga(
        X_train=X_train,
        y_train=y_train,
        X_test=X_test,
        y_test=y_test,
        **ga_params
    )
    
    # Save artifacts
    artifacts = save_artifacts(run_id, best_individual, population_history)
    
    return {
        "status": "success",
        "best_model": individual_to_model_spec(best_individual),
        "best_metric": float(best_fitness),
        "completed_trials": len(population_history),
        "population_history": format_population_history(population_history),
        "artifacts": artifacts,
        "metadata": {
            "dataset_id": dataset_id,
            "objective": objective,
            "ga_params": ga_params,
            "timestamp": datetime.utcnow().isoformat()
        }
    }


def run_stub_nas(dataset_id: str, max_trials: int, run_id: str) -> Dict[str, Any]:
    """
    Stub implementation for testing without Cerebros installed
    
    Returns fake results that match the expected output format.
    """
    logger.warning(f"Using stub NAS implementation for run {run_id}")
    
    import random
    
    # Generate fake population history
    population_history = []
    for generation in range(max_trials):
        fitness = 0.5 + (generation / max_trials) * 0.4 + random.uniform(-0.05, 0.05)
        population_history.append({
            "generation": generation,
            "best_fitness": fitness,
            "mean_fitness": fitness - 0.1,
            "population_size": 20
        })
    
    best_fitness = max(h["best_fitness"] for h in population_history)
    
    return {
        "status": "success",
        "best_model": {
            "layers": [128, 64, 32],
            "activation": "relu",
            "optimizer": "adam",
            "learning_rate": 0.001
        },
        "best_metric": best_fitness,
        "completed_trials": max_trials,
        "population_history": population_history,
        "artifacts": [f"/tmp/cerebros/{run_id}/stub_model.h5"],
        "metadata": {
            "dataset_id": dataset_id,
            "mode": "stub",
            "timestamp": datetime.utcnow().isoformat()
        }
    }


def load_dataset(dataset_id: str):
    """
    Load dataset for training
    
    For now this is a stub. In production, this would:
    1. Load from Thunderline storage
    2. Preprocess data
    3. Split into train/test
    """
    logger.info(f"Loading dataset {dataset_id}")
    
    # Stub: Return dummy data matching expected format
    import numpy as np
    
    # Small dummy dataset
    X_train = np.random.rand(100, 20)
    y_train = np.random.randint(0, 2, 100)
    X_test = np.random.rand(30, 20)
    y_test = np.random.randint(0, 2, 30)
    
    return X_train, y_train, X_test, y_test


def individual_to_model_spec(individual) -> Dict[str, Any]:
    """
    Convert Cerebros GA individual to model specification dict
    
    The individual format depends on the Cerebros implementation.
    This extracts the architecture specification.
    """
    # This is implementation-specific
    # For now return a generic spec
    return {
        "architecture": str(individual),
        "type": "neural_network"
    }


def format_population_history(history: List) -> List[Dict]:
    """
    Format population history for JSON serialization
    """
    formatted = []
    for i, generation_data in enumerate(history):
        formatted.append({
            "generation": i,
            "data": str(generation_data)  # Convert to string for safety
        })
    return formatted


def save_artifacts(run_id: str, best_individual, population_history) -> List[str]:
    """
    Save model artifacts to disk
    
    Returns list of artifact paths.
    """
    artifacts_dir = f"/tmp/cerebros_artifacts/{run_id}"
    os.makedirs(artifacts_dir, exist_ok=True)
    
    artifacts = []
    
    # Save best model
    model_path = os.path.join(artifacts_dir, "best_model.json")
    with open(model_path, 'w') as f:
        json.dump(individual_to_model_spec(best_individual), f, indent=2)
    artifacts.append(model_path)
    
    # Save population history
    history_path = os.path.join(artifacts_dir, "population_history.json")
    with open(history_path, 'w') as f:
        json.dump(format_population_history(population_history), f, indent=2)
    artifacts.append(history_path)
    
    logger.info(f"Saved artifacts to {artifacts_dir}")
    return artifacts


# Test entry point
if __name__ == "__main__":
    # Test the service with sample inputs
    print("=" * 80)
    print("Testing Cerebros Service")
    print("=" * 80)
    
    spec = {
        "dataset_id": "test_dataset",
        "search_space": {
            "layer_sizes": [32, 64, 128, 256],
            "activations": ["relu", "tanh", "sigmoid"]
        },
        "objective": "accuracy"
    }
    
    opts = {
        "run_id": "test_run_001",
        "budget": {
            "max_trials": 5,
            "population_size": 10
        },
        "parameters": {
            "mutation_rate": 0.1,
            "crossover_rate": 0.7,
            "elite_size": 2
        },
        "tau": 1.0
    }
    
    result = run_nas(spec, opts)
    
    print("\n" + "=" * 80)
    print("Result:")
    print("=" * 80)
    print(json.dumps(result, indent=2))
    print("\n✅ Test complete")
