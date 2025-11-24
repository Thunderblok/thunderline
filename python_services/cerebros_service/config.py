"""
Configuration for Cerebros service.

Environment variables:
- CEREBROS_SERVICE_ID: Unique service identifier (default: cerebros-1)
- THUNDERLINE_URL: Thunderline base URL (default: http://localhost:4000)
- MLFLOW_TRACKING_URI: MLflow tracking URI (default: http://localhost:5000)
- CEREBROS_POLL_INTERVAL: Seconds between job polls (default: 5)
- CEREBROS_HEARTBEAT_INTERVAL: Seconds between heartbeats (default: 30)
"""
import os
from dataclasses import dataclass


@dataclass
class CerebrosConfig:
    """Cerebros service configuration."""

    service_id: str = "cerebros-1"
    thunderline_url: str = "http://localhost:4000"
    mlflow_url: str = "http://localhost:5000"
    poll_interval: int = 5
    heartbeat_interval: int = 30

    @classmethod
    def from_env(cls):
        """Load configuration from environment variables."""
        return cls(
            service_id=os.getenv("CEREBROS_SERVICE_ID", cls.service_id),
            thunderline_url=os.getenv("THUNDERLINE_URL", cls.thunderline_url),
            mlflow_url=os.getenv("MLFLOW_TRACKING_URI", cls.mlflow_url),
            poll_interval=int(os.getenv("CEREBROS_POLL_INTERVAL", str(cls.poll_interval))),
            heartbeat_interval=int(
                os.getenv("CEREBROS_HEARTBEAT_INTERVAL", str(cls.heartbeat_interval))
            ),
        )
