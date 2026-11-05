"""Local Qiskit Aer provider (synchronous, free). Used for ``qops run --local`` and tests.

Backends:

- ``exact``: noiseless statevector probabilities (``shots=None``) or seeded sampling.
- ``sampler``: noiseless shot-based sampling (``shots`` required).
"""

from __future__ import annotations

import uuid

from qiskit import QuantumCircuit
from qiskit.quantum_info import Statevector
from qiskit.transpiler import Target
from qiskit_aer import AerSimulator

from qops_core.models import CircuitResult, ResultSet
from qops_providers.base import (
    Capabilities,
    CostEstimate,
    JobSpec,
    JobStatus,
    ProviderError,
    ProviderJobRef,
    validate_job,
)

_CAPABILITIES = {
    "exact": Capabilities(
        mid_circuit_measurement=False, per_shot_memory=True, exact_probabilities=True
    ),
    "sampler": Capabilities(mid_circuit_measurement=True, per_shot_memory=True),
}


def exact_distribution(circuit: QuantumCircuit) -> dict[str, float]:
    """Exact outcome probabilities of a circuit whose measurements all come at the end."""
    if circuit.num_clbits == 0:
        raise ProviderError("exact mode needs a circuit with measurements")
    unitary_part = circuit.remove_final_measurements(inplace=False)
    if unitary_part.num_clbits:
        raise ProviderError("exact mode supports final measurements only")
    qubit_for_clbit: dict[int, int] = {}
    for instruction in circuit.data:
        if instruction.operation.name == "measure":
            qubit = circuit.find_bit(instruction.qubits[0]).index
            clbit = circuit.find_bit(instruction.clbits[0]).index
            qubit_for_clbit[clbit] = qubit
    probs = Statevector(unitary_part).probabilities_dict()
    out: dict[str, float] = {}
    for qubit_bits, p in probs.items():
        if p < 1e-15:
            continue
        # Statevector keys are big-endian strings with qubit 0 rightmost; map onto clbit order.
        bits = ["0"] * circuit.num_clbits
        for clbit, qubit in qubit_for_clbit.items():
            bits[circuit.num_clbits - 1 - clbit] = qubit_bits[len(qubit_bits) - 1 - qubit]
        key = "".join(bits)
        out[key] = out.get(key, 0.0) + float(p)
    return out


class AerProvider:
    name = "aer"

    def __init__(self) -> None:
        self._simulator = AerSimulator()
        self._results: dict[str, ResultSet] = {}

    def backends(self) -> list[str]:
        return list(_CAPABILITIES)

    def capabilities(self, backend: str) -> Capabilities:
        try:
            return _CAPABILITIES[backend]
        except KeyError as exc:
            raise ProviderError(f"aer: unknown backend '{backend}'") from exc

    def target(self, backend: str) -> Target:
        self.capabilities(backend)
        return self._simulator.target

    def estimate_cost(self, job: JobSpec) -> CostEstimate:
        return CostEstimate(qpu_seconds=0.0, usd=0.0)

    def submit(self, job: JobSpec) -> ProviderJobRef:
        validate_job(self, job)
        if job.shots is None:
            results = [
                CircuitResult(probabilities=exact_distribution(c), shots=None) for c in job.circuits
            ]
        else:
            run = self._simulator.run(list(job.circuits), shots=job.shots, seed_simulator=job.seed)
            raw = run.result()
            results = [
                CircuitResult.from_counts(raw.get_counts(i)) for i in range(len(job.circuits))
            ]
        ref = ProviderJobRef(provider=self.name, backend=job.backend, job_id=uuid.uuid4().hex)
        self._results[ref.job_id] = ResultSet(
            results=results, metadata={"provider": self.name, "backend": job.backend}
        )
        return ref

    def status(self, ref: ProviderJobRef) -> JobStatus:
        return JobStatus.DONE if ref.job_id in self._results else JobStatus.FAILED

    def result(self, ref: ProviderJobRef) -> ResultSet:
        try:
            return self._results.pop(ref.job_id)
        except KeyError as exc:
            raise ProviderError(f"aer: unknown job '{ref.job_id}'") from exc

    def cancel(self, ref: ProviderJobRef) -> None:
        self._results.pop(ref.job_id, None)
