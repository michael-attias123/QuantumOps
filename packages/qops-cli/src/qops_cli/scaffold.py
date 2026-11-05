"""``qops new algorithm``: scaffold a pure-Qiskit algorithm that satisfies the L0 contract."""

from __future__ import annotations

import re
from pathlib import Path

_NAME = re.compile(r"^[a-z][a-z0-9_]*$")

_SAMPLING = '''"""{name}: sampling algorithm (pure Qiskit, no platform imports)."""

from qiskit import QuantumCircuit


class Algorithm:
    def __init__(self, config: dict) -> None:
        self.num_qubits = int(config.get("num_qubits", 2))

    def circuits(self) -> list[QuantumCircuit]:
        qc = QuantumCircuit(self.num_qubits)
        qc.h(range(self.num_qubits))
        qc.measure_all()
        return [qc]

    def analyze(self, distributions: list[dict[str, float]]) -> dict:
        return {{"outcomes": len(distributions[0])}}
'''

_VARIATIONAL = '''"""{name}: variational algorithm (pure Qiskit, no platform imports)."""

from qiskit import QuantumCircuit
from qiskit.circuit.library import real_amplitudes
from qiskit.quantum_info import SparsePauliOp


class Algorithm:
    def __init__(self, config: dict) -> None:
        self.reps = int(config.get("reps", 1))

    def ansatz(self) -> QuantumCircuit:
        return real_amplitudes(2, reps=self.reps)

    def hamiltonian(self) -> SparsePauliOp:
        return SparsePauliOp.from_list([("ZZ", 1.0), ("XI", 0.5)])

    def initial_point(self) -> list[float]:
        return [0.1] * self.ansatz().num_parameters
'''

_CONFIG = {"sampling": "  num_qubits: 2", "variational": "  reps: 1"}


def scaffold_algorithm(base: Path, name: str, kind: str) -> Path:
    if not _NAME.match(name):
        raise ValueError("algorithm name must be snake_case (letters, digits, underscores)")
    if kind not in _CONFIG:
        raise ValueError(f"unsupported kind '{kind}'")
    target = base / name
    if target.exists():
        raise FileExistsError(f"{target} already exists")
    target.mkdir(parents=True)
    template = _SAMPLING if kind == "sampling" else _VARIATIONAL
    (target / "algorithm.py").write_text(template.format(name=name), encoding="utf-8")
    (target / "algorithm.yaml").write_text(
        f"name: {name}\nkind: {kind}\ndescription: TODO\nconfig:\n{_CONFIG[kind]}\n",
        encoding="utf-8",
    )
    return target
