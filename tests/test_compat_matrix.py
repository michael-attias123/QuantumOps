"""Version pin matrix (P1): Qiskit 2.x together with the packages later phases depend on.

Runs only when the ``compat`` dependency group is installed (CI job ``compat``, amd64 + arm64):
``uv sync --group compat``.
"""

import importlib

import pytest

MODULES = ["mthree", "mitiq", "qiskit_ibm_runtime", "qiskit_ionq", "qiskit_braket_provider"]


@pytest.mark.parametrize("module", MODULES)
def test_imports_alongside_qiskit_2(module: str) -> None:
    pytest.importorskip(module)
    qiskit = importlib.import_module("qiskit")
    assert int(qiskit.__version__.split(".")[0]) == 2
    importlib.import_module(module)
