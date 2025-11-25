"""
Cerebros Core - NAS Algorithm & LLM Utilities

Contains:
    - cerebros: Neural Architecture Search components
    - cerebrosllmutils: LLM training utilities (CerebrosNotGPT, etc.)
    - vanilladatasets: Sample datasets for testing
"""

import sys
from pathlib import Path

# Add core subdirectories to path for imports
_core_path = Path(__file__).parent
sys.path.insert(0, str(_core_path))
