"""
Cerebros Service: Training service that coordinates with Thunderline.

This service:
1. Registers itself with Thunderline on startup
2. Sends periodic heartbeats
3. Polls for queued training jobs
4. Executes training using POC logic
5. Reports progress and results back to Thunderline
6. Logs to MLflow (via MLFLOW_TRACKING_URI env var)
"""
import os
import sys
import time
import logging
import threading
import signal
from typing import Optional, Dict, Any

# Add parent directory to path for POC imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "deploy"))

from thunderline_client import ThunderlineClient
from job_executor import JobExecutor
from .direct_entry import run_nas

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class CerebrosService:
    """Main service class for Cerebros training worker."""

    def __init__(
        self,
        service_id: str,
        thunderline_url: str,
        mlflow_url: Optional[str] = None,
        poll_interval: int = 5,
        heartbeat_interval: int = 30,
    ):
        """
        Initialize Cerebros service.

        Args:
            service_id: Unique service identifier (e.g., "cerebros-1")
            thunderline_url: Thunderline base URL (e.g., "http://localhost:4000")
            mlflow_url: MLflow tracking URI (e.g., "http://localhost:5000")
            poll_interval: Seconds between job polls
            heartbeat_interval: Seconds between heartbeats
        """
        self.service_id = service_id
        self.poll_interval = poll_interval
        self.heartbeat_interval = heartbeat_interval
        self.running = False
        self.current_job = None

        # Initialize Thunderline client
        self.client = ThunderlineClient(thunderline_url)

        # Set MLflow tracking URI if provided
        if mlflow_url:
            os.environ["MLFLOW_TRACKING_URI"] = mlflow_url
            logger.info(f"MLflow tracking URI set to: {mlflow_url}")

        # Initialize job executor (wraps POC logic)
        self.executor = JobExecutor(self.client)

        # Heartbeat thread
        self.heartbeat_thread = None

    def start(self):
        """
        Start the service.

        1. Registers with Thunderline
        2. Starts heartbeat thread
        3. Begins job polling loop
        """
        logger.info(f"Starting Cerebros service: {self.service_id}")

        # Register service
        try:
            self._register()
        except Exception as e:
            logger.error(f"Failed to register service: {e}")
            return

        # Start heartbeat thread
        self.running = True
        self.heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        self.heartbeat_thread.start()

        # Start job polling loop (main thread)
        try:
            self._job_polling_loop()
        except KeyboardInterrupt:
            logger.info("Received interrupt signal")
        finally:
            self.stop()

    def stop(self):
        """Stop the service gracefully."""
        logger.info("Stopping Cerebros service")
        self.running = False

        # Deregister from Thunderline
        try:
            self.client.deregister_service(self.service_id)
        except Exception as e:
            logger.error(f"Failed to deregister service: {e}")

        logger.info("Service stopped")

    def _register(self):
        """Register service with Thunderline."""
        capabilities = {
            "training": True,
            "hyperparameter_optimization": True,
            "frameworks": ["tensorflow", "keras"],
        }

        metadata = {
            "version": "1.0.0",
            "based_on": "cerebros_runner_poc.py",
        }

        self.client.register_service(
            service_id=self.service_id,
            service_type="cerebros",
            name=f"Cerebros Training Service ({self.service_id})",
            host="localhost",
            capabilities=capabilities,
            metadata=metadata,
        )

        logger.info(f"Service registered: {self.service_id}")

    def _heartbeat_loop(self):
        """Send periodic heartbeats to Thunderline."""
        while self.running:
            try:
                status = "healthy"

                # Update metadata with current job info
                metadata = {}
                if self.current_job:
                    metadata["current_job_id"] = self.current_job
                    status = "busy"

                self.client.send_heartbeat(
                    service_id=self.service_id, status=status, metadata=metadata
                )

                logger.debug(f"Heartbeat sent (status: {status})")

            except Exception as e:
                logger.error(f"Heartbeat failed: {e}")

            time.sleep(self.heartbeat_interval)

    def _job_polling_loop(self):
        """Poll for jobs and execute them."""
        logger.info("Starting job polling loop")

        while self.running:
            try:
                # Poll for next job
                job = self.client.poll_job()

                if job is None:
                    # No jobs available, wait and retry
                    logger.debug(f"No jobs available, sleeping {self.poll_interval}s")
                    time.sleep(self.poll_interval)
                    continue

                # Execute job
                self.current_job = job["id"]
                logger.info(f"Picked up job: {job['id']}")

                try:
                    self.executor.execute_job(job)
                    logger.info(f"Job {job['id']} completed successfully")

                except Exception as e:
                    logger.error(f"Job {job['id']} failed: {e}", exc_info=True)

                finally:
                    self.current_job = None

            except Exception as e:
                logger.error(f"Error in job polling loop: {e}", exc_info=True)
                time.sleep(self.poll_interval)


def main():
    """Main entry point."""
    # Configuration from environment
    SERVICE_ID = os.getenv("CEREBROS_SERVICE_ID", "cerebros-1")
    THUNDERLINE_URL = os.getenv("THUNDERLINE_URL", "http://localhost:4000")
    MLFLOW_URL = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
    POLL_INTERVAL = int(os.getenv("CEREBROS_POLL_INTERVAL", "5"))
    HEARTBEAT_INTERVAL = int(os.getenv("CEREBROS_HEARTBEAT_INTERVAL", "30"))

    logger.info("=" * 80)
    logger.info("Cerebros Training Service")
    logger.info("=" * 80)
    logger.info(f"Service ID: {SERVICE_ID}")
    logger.info(f"Thunderline URL: {THUNDERLINE_URL}")
    logger.info(f"MLflow URL: {MLFLOW_URL}")
    logger.info(f"Poll Interval: {POLL_INTERVAL}s")
    logger.info(f"Heartbeat Interval: {HEARTBEAT_INTERVAL}s")
    logger.info("=" * 80)

    # Create and start service
    service = CerebrosService(
        service_id=SERVICE_ID,
        thunderline_url=THUNDERLINE_URL,
        mlflow_url=MLFLOW_URL,
        poll_interval=POLL_INTERVAL,
        heartbeat_interval=HEARTBEAT_INTERVAL,
    )

    # Handle graceful shutdown
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}")
        service.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start service
    service.start()


if __name__ == "__main__":
    main()
