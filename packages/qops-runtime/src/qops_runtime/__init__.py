"""Workflow entrypoints for L1 (prepare/submit) and L3 (postprocess/finalize)."""

from qops_runtime.local import LocalRunOptions, RunReport, run_local

__version__ = "0.0.1"

__all__ = ["LocalRunOptions", "RunReport", "__version__", "run_local"]
