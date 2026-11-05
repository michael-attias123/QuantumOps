"""Provider-neutral data models shared by every layer."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class ExperimentKind(StrEnum):
    """Which execution loop the platform runs for an algorithm (ARCHITECTURE §6)."""

    SAMPLING = "sampling"
    VARIATIONAL = "variational"
    QEC_MEMORY = "qec-memory"


Distribution = dict[str, float]
"""Measurement outcome probabilities keyed by bitstring (Qiskit order: clbit 0 is rightmost)."""


@dataclass(frozen=True)
class CircuitResult:
    """Outcome of one circuit. ``shots is None`` means exact (noiseless, infinite-shot) probabilities."""

    probabilities: Distribution
    shots: int | None
    counts: dict[str, int] | None = None

    @classmethod
    def from_counts(cls, counts: Mapping[str, int]) -> CircuitResult:
        total = sum(counts.values())
        if total <= 0:
            raise ValueError("counts must contain at least one shot")
        return cls(
            probabilities={k: v / total for k, v in counts.items()},
            shots=total,
            counts=dict(counts),
        )


@dataclass(frozen=True)
class ResultSet:
    """Results for every circuit of one job, in submission order."""

    results: list[CircuitResult]
    metadata: dict[str, Any] = field(default_factory=dict)

    def distributions(self) -> list[Distribution]:
        return [r.probabilities for r in self.results]
