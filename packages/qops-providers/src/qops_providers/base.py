"""Provider interface shared by QPU providers (L2) and, from P9, remote GPU providers.

Every provider is asynchronous by contract: ``submit`` returns a job reference, ``status`` reports
progress and ``result`` returns a provider-neutral ``ResultSet``. Synchronous backends such as the
local Aer provider simply finish during ``submit``.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Protocol, runtime_checkable

from qiskit import QuantumCircuit
from qiskit.transpiler import Target

from qops_core.models import ResultSet


class JobStatus(StrEnum):
    QUEUED = "QUEUED"
    RUNNING = "RUNNING"
    DONE = "DONE"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"

    @property
    def is_terminal(self) -> bool:
        return self in {JobStatus.DONE, JobStatus.FAILED, JobStatus.CANCELLED}


@dataclass(frozen=True)
class Capabilities:
    paid: bool = False
    mid_circuit_measurement: bool = False
    per_shot_memory: bool = False
    exact_probabilities: bool = False
    max_shots: int = 100_000
    max_circuits_per_job: int = 300


@dataclass(frozen=True)
class JobSpec:
    """One provider job. ``shots=None`` requests exact probabilities (simulators only)."""

    circuits: Sequence[QuantumCircuit]
    backend: str
    shots: int | None
    seed: int | None = None
    tags: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class ProviderJobRef:
    provider: str
    backend: str
    job_id: str


@dataclass(frozen=True)
class CostEstimate:
    qpu_seconds: float
    usd: float

    @property
    def is_free(self) -> bool:
        return self.usd == 0.0


class ProviderError(RuntimeError):
    """A provider rejected or failed a request."""


@runtime_checkable
class QuantumProvider(Protocol):
    name: str

    def backends(self) -> list[str]: ...

    def capabilities(self, backend: str) -> Capabilities: ...

    def target(self, backend: str) -> Target: ...

    def estimate_cost(self, job: JobSpec) -> CostEstimate: ...

    def submit(self, job: JobSpec) -> ProviderJobRef: ...

    def status(self, ref: ProviderJobRef) -> JobStatus: ...

    def result(self, ref: ProviderJobRef) -> ResultSet: ...

    def cancel(self, ref: ProviderJobRef) -> None: ...


def validate_job(provider: QuantumProvider, job: JobSpec) -> None:
    """Reject jobs that exceed the backend's declared capabilities before submission."""
    if job.backend not in provider.backends():
        raise ProviderError(f"{provider.name}: unknown backend '{job.backend}'")
    caps = provider.capabilities(job.backend)
    if job.shots is None and not caps.exact_probabilities:
        raise ProviderError(f"{provider.name}/{job.backend}: exact probabilities not supported")
    if job.shots is not None and not 0 < job.shots <= caps.max_shots:
        raise ProviderError(f"{provider.name}/{job.backend}: shots must be in 1..{caps.max_shots}")
    if not 0 < len(job.circuits) <= caps.max_circuits_per_job:
        raise ProviderError(
            f"{provider.name}/{job.backend}: 1..{caps.max_circuits_per_job} circuits per job"
        )


def describe(provider: QuantumProvider) -> dict[str, Any]:
    return {
        "name": provider.name,
        "backends": {b: provider.capabilities(b).__dict__ for b in provider.backends()},
    }
