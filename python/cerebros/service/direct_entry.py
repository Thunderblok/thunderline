"""
Direct Entry Point for Cerebros Training.

This module provides a direct execution path for training jobs, bypassing the
polling service. It is used by SnexInvoker to run training synchronously
within the Elixir node's Python environment.
"""
import os
import logging
import json
from typing import Dict, Any, Optional
from pathlib import Path

# Import JobExecutor from the same package
from .job_executor import JobExecutor

logger = logging.getLogger(__name__)

class DirectClient:
    """
    Mock ThunderlineClient for direct execution.
    
    This class mimics the interface of ThunderlineClient but operates locally,
    reading data from disk and logging status updates instead of making HTTP requests.
    """
    def __init__(self, data_dir: str, output_dir: str):
        self.data_dir = Path(data_dir)
        self.output_dir = Path(output_dir)
        self.metrics = {}
        self.status_history = []
        
        # Ensure directories exist
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def get_corpus_path(self, dataset_id: str) -> str:
        """
        Resolve dataset ID to a file path.
        
        If dataset_id is an absolute path, return it.
        Otherwise, look for it in data_dir.
        """
        if os.path.isabs(dataset_id):
            return dataset_id
            
        # Try exact match
        path = self.data_dir / dataset_id
        if path.exists():
            return str(path)
            
        # Try with .jsonl extension
        path = self.data_dir / f"{dataset_id}.jsonl"
        if path.exists():
            return str(path)
            
        # Fallback: return as is (JobExecutor might fail if not found)
        return str(path)

    def update_job_status(self, job_id: str, status: str, **kwargs):
        """Log job status update."""
        logger.info(f"Job {job_id} status: {status}, details: {kwargs}")
        self.status_history.append({"status": status, **kwargs})

    def update_job_metrics(self, job_id: str, metrics: Dict[str, Any], phase: Optional[Any] = None):
        """Log job metrics."""
        logger.info(f"Job {job_id} metrics (phase={phase}): {metrics}")
        for k, v in metrics.items():
            if k not in self.metrics:
                self.metrics[k] = []
            self.metrics[k].append(v)

    def add_checkpoint(self, job_id: str, path: str):
        """Log checkpoint creation."""
        logger.info(f"Job {job_id} checkpoint: {path}")

    def log_metric(self, job_id: str, name: str, value: float, step: int = None):
        """Log single metric."""
        self.update_job_metrics(job_id, {name: value}, phase=step)


def run_nas(spec: Dict[str, Any], opts: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute a NAS training job directly.
    
    Args:
        spec: Job specification containing:
            - model_id: str
            - dataset_id: str
            - hyperparameters: dict
        opts: Execution options containing:
            - data_dir: str (default: ./data)
            - output_dir: str (default: ./output)
            - convert_to_onnx: bool (default: True)
            
    Returns:
        Dict containing execution results, paths, and metrics.
    """
    # Setup logging
    logging.basicConfig(level=logging.INFO)
    
    # Extract options
    data_dir = opts.get("data_dir", "./data")
    output_dir = opts.get("output_dir", "./output")
    convert_onnx = opts.get("convert_to_onnx", True)
    
    # Create mock client
    client = DirectClient(data_dir, output_dir)
    
    # Construct job object
    job_id = spec.get("model_id", "direct_job")
    job = {
        "id": job_id,
        "training_dataset_id": spec.get("dataset_id", "dataset"),
        "model_id": spec.get("model_id", "model"),
        "hyperparameters": spec.get("hyperparameters", {})
    }
    
    logger.info(f"Starting direct NAS run for job {job_id}")
    
    try:
        # Initialize executor with direct client
        # JobExecutor expects output_dir to be passed or uses ./checkpoints
        # We'll patch it or rely on its default if not passed in __init__
        # Looking at JobExecutor code, it sets self.checkpoint_dir = Path("./checkpoints")
        # We should probably override that if possible, but JobExecutor doesn't take it in __init__.
        # We can monkey-patch it or just let it use ./checkpoints.
        # Actually, let's subclass or modify JobExecutor instance.
        
        executor = JobExecutor(client)
        executor.checkpoint_dir = Path(output_dir) / job_id
        executor.checkpoint_dir.mkdir(parents=True, exist_ok=True)
        
        # Execute training
        executor.execute_job(job)
        
        # Collect results
        result = {
            "status": "completed",
            "job_id": job_id,
            "metrics": client.metrics,
            "checkpoints_dir": str(executor.checkpoint_dir)
        }
        
        # Find final model
        final_model_path = executor.checkpoint_dir / f"{job_id}_final.keras"
        if final_model_path.exists():
            result["keras_path"] = str(final_model_path)
            
            # Convert to ONNX if requested
            if convert_onnx:
                try:
                    from cerebros.onnx.convert import convert_to_onnx
                    onnx_path = executor.checkpoint_dir / f"{job_id}.onnx"
                    convert_to_onnx(str(final_model_path), str(onnx_path))
                    result["onnx_path"] = str(onnx_path)
                    logger.info(f"Converted to ONNX: {onnx_path}")
                except ImportError:
                    logger.warning("cerebros.onnx.convert not found, skipping ONNX conversion")
                except Exception as e:
                    logger.error(f"ONNX conversion failed: {e}")
                    result["onnx_error"] = str(e)
        else:
            logger.warning(f"Final model not found at {final_model_path}")
            result["status"] = "completed_no_model"
            
        return result

    except Exception as e:
        logger.exception("Direct NAS run failed")
        return {
            "status": "failed",
            "error": str(e)
        }
