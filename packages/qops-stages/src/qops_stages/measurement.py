"""Measurement grouping and expectation values from probabilities (Sampler-everywhere, ADR 0005).

L1 builds one measurement circuit per qubit-wise-commuting group of Pauli terms; L3 turns the
measured distributions back into ``<H>``.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from qiskit import QuantumCircuit
from qiskit.quantum_info import SparsePauliOp

from qops_core.models import Distribution


@dataclass(frozen=True)
class MeasurementGroup:
    """Qubit-wise commuting Pauli terms measured together in one basis."""

    observable: SparsePauliOp
    basis: tuple[str, ...]  # per qubit (index 0 = qubit 0): "X", "Y", "Z" or "I"


def group_observable(observable: SparsePauliOp) -> list[MeasurementGroup]:
    groups = []
    for group in observable.group_commuting(qubit_wise=True):
        basis = ["I"] * observable.num_qubits
        for pauli in group.paulis:
            for qubit in range(observable.num_qubits):
                z, x = bool(pauli.z[qubit]), bool(pauli.x[qubit])
                letter = "Y" if (z and x) else "X" if x else "Z" if z else "I"
                if letter != "I":
                    basis[qubit] = letter
        groups.append(MeasurementGroup(observable=group, basis=tuple(basis)))
    return groups


def measurement_circuit(state_prep: QuantumCircuit, group: MeasurementGroup) -> QuantumCircuit:
    """Append basis rotations for ``group`` and measure every qubit (clbit i <- qubit i)."""
    circuit = state_prep.copy()
    for qubit, letter in enumerate(group.basis):
        if letter == "X":
            circuit.h(qubit)
        elif letter == "Y":
            circuit.sdg(qubit)
            circuit.h(qubit)
    circuit.measure_all()
    return circuit


def expectation_from_distribution(group: MeasurementGroup, distribution: Distribution) -> float:
    """``<group.observable>`` from outcome probabilities of ``measurement_circuit``."""
    total = 0.0
    for pauli, coeff in zip(group.observable.paulis, group.observable.coeffs, strict=True):
        support = [q for q in range(pauli.num_qubits) if pauli.z[q] or pauli.x[q]]
        value = 0.0
        for bitstring, probability in distribution.items():
            parity = sum(bitstring[len(bitstring) - 1 - q] == "1" for q in support) % 2
            value += probability * (-1.0 if parity else 1.0)
        total += float(coeff.real) * value
    return total


def energy(groups: Sequence[MeasurementGroup], distributions: Sequence[Distribution]) -> float:
    if len(groups) != len(distributions):
        raise ValueError("one distribution per measurement group is required")
    return sum(
        expectation_from_distribution(g, d) for g, d in zip(groups, distributions, strict=True)
    )
