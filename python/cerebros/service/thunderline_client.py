"""
Thunderline Client: HTTP client for coordinating with Thunderline service.

This client handles:
- Service registration
- Heartbeat reporting
- Job polling
- Status updates
- Metrics reporting
- Checkpoint uploads
- Dataset corpus fetching
"""
import requests
import logging
from typing import Optional, Dict, Any, List
from datetime import datetime

logger = logging.getLogger(__name__)


class ThunderlineClient:
    """HTTP client for Thunderline service coordination."""

    def __init__(self, base_url: str = "http://localhost:4000"):
        """
        Initialize Thunderline client.

        Args:
            base_url: Base URL of Thunderline service (e.g., "http://localhost:4000")
        """
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
            "User-Agent": "Cerebros-Service/1.0"
        })

    # Service Registry APIs

    def register_service(
        self,
        service_id: str,
        service_type: str,
        name: str,
        host: str = "localhost",
        port: Optional[int] = None,
        capabilities: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Register service with Thunderline.

        Args:
            service_id: Unique service identifier (e.g., "cerebros-1")
            service_type: Type of service (e.g., "cerebros", "mlflow")
            name: Human-readable service name
            host: Hostname where service is running
            port: Port number (if service has HTTP endpoint)
            capabilities: Service capabilities metadata
            metadata: Additional metadata

        Returns:
            Registered service data

        Raises:
            requests.HTTPError: If registration fails
        """
        data = {
            "service_id": service_id,
            "service_type": service_type,
            "name": name,
            "host": host,
            "capabilities": capabilities or {},
            "metadata": metadata or {},
        }

        if port is not None:
            data["port"] = port

        url = f"{self.base_url}/api/registry/register"
        logger.info(f"Registering service: {service_id} at {url}")
        logger.debug(f"Registration payload: {data}")

        response = self.session.post(url, json=data)
        
        if not response.ok:
            logger.error(f"Registration failed with status {response.status_code}")
            logger.error(f"Response body: {response.text}")
        
        response.raise_for_status()

        service_data = response.json()
        logger.info(f"Service registered successfully: {service_id}")
        return service_data

    def send_heartbeat(
        self,
        service_id: str,
        status: str = "healthy",
        capabilities: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Send heartbeat for service.

        Args:
            service_id: Service identifier
            status: Current status ("healthy", "unhealthy", etc.)
            capabilities: Updated capabilities
            metadata: Updated metadata

        Returns:
            Updated service data

        Raises:
            requests.HTTPError: If heartbeat fails
        """
        data = {"status": status}

        if capabilities is not None:
            data["capabilities"] = capabilities

        if metadata is not None:
            data["metadata"] = metadata

        url = f"{self.base_url}/api/registry/{service_id}/heartbeat"
        logger.debug(f"Sending heartbeat for service: {service_id}")

        response = self.session.patch(url, json=data)
        response.raise_for_status()

        return response.json()

    def deregister_service(self, service_id: str) -> None:
        """
        Deregister service from Thunderline.

        Args:
            service_id: Service identifier

        Raises:
            requests.HTTPError: If deregistration fails
        """
        url = f"{self.base_url}/api/registry/{service_id}"
        logger.info(f"Deregistering service: {service_id}")

        response = self.session.delete(url)
        response.raise_for_status()

        logger.info(f"Service deregistered: {service_id}")

    # Job Coordination APIs

    def poll_job(self) -> Optional[Dict[str, Any]]:
        """
        Poll for next queued training job.

        Returns:
            Job data if available, None if no jobs queued

        Raises:
            requests.HTTPError: If poll fails
        """
        url = f"{self.base_url}/api/jobs/poll"
        logger.debug("Polling for jobs")

        response = self.session.get(url)

        if response.status_code == 204:
            logger.debug("No jobs available")
            return None

        response.raise_for_status()
        job = response.json()

        logger.info(f"Retrieved job: {job['id']}")
        return job

    def update_job_status(
        self, job_id: str, status: str, error_message: Optional[str] = None, fine_tuned_model: Optional[str] = None
    ) -> None:
        """
        Update job status.

        Args:
            job_id: Job UUID
            status: New status ("queued", "training", "completed", "failed")
            error_message: Error message (for failed status)
            fine_tuned_model: Model identifier (for completed status)

        Raises:
            requests.HTTPError: If update fails
        """
        data = {"status": status}

        if error_message is not None:
            data["error_message"] = error_message

        if fine_tuned_model is not None:
            data["fine_tuned_model"] = fine_tuned_model

        url = f"{self.base_url}/api/jobs/{job_id}/status"
        logger.info(f"Updating job {job_id} status to: {status}")

        response = self.session.patch(url, json=data)
        response.raise_for_status()

        logger.debug(f"Job {job_id} status updated")

    def update_job_metrics(
        self, job_id: str, metrics: Dict[str, float], phase: Optional[int] = None
    ) -> None:
        """
        Update job training metrics.

        Args:
            job_id: Job UUID
            metrics: Metrics dict (e.g., {"perplexity": 2.45, "loss": 0.123})
            phase: Current training phase/epoch

        Raises:
            requests.HTTPError: If update fails
        """
        data = {"metrics": metrics}

        if phase is not None:
            data["phase"] = phase

        url = f"{self.base_url}/api/jobs/{job_id}/metrics"
        logger.debug(f"Updating job {job_id} metrics: {metrics}")

        response = self.session.patch(url, json=data)
        response.raise_for_status()

    def add_checkpoint(self, job_id: str, checkpoint_url: str) -> None:
        """
        Add checkpoint URL to job.

        Args:
            job_id: Job UUID
            checkpoint_url: Path or URL to checkpoint file

        Raises:
            requests.HTTPError: If update fails
        """
        data = {"checkpoint_url": checkpoint_url}

        url = f"{self.base_url}/api/jobs/{job_id}/checkpoints"
        logger.info(f"Adding checkpoint to job {job_id}: {checkpoint_url}")

        response = self.session.post(url, json=data)
        response.raise_for_status()

    def get_corpus_path(self, dataset_id: str) -> str:
        """
        Get corpus JSONL file path for dataset.

        Args:
            dataset_id: Dataset UUID

        Returns:
            Absolute path to corpus JSONL file

        Raises:
            requests.HTTPError: If fetch fails
        """
        url = f"{self.base_url}/api/datasets/{dataset_id}/corpus"
        logger.debug(f"Fetching corpus path for dataset: {dataset_id}")

        response = self.session.get(url)
        response.raise_for_status()

        data = response.json()
        corpus_path = data["corpus_path"]

        logger.info(f"Corpus path for dataset {dataset_id}: {corpus_path}")
        return corpus_path
