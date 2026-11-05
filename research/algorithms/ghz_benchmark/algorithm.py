"""GHZ benchmark: smoke test for the whole pipeline (pure Qiskit, no platform imports)."""

from qiskit import QuantumCircuit


class Algorithm:
    def __init__(self, config: dict) -> None:
        self.n = int(config.get("num_qubits", 3))
        if self.n < 2:
            raise ValueError("num_qubits must be >= 2")

    def _ghz(self) -> QuantumCircuit:
        qc = QuantumCircuit(self.n)
        qc.h(0)
        for q in range(self.n - 1):
            qc.cx(q, q + 1)
        return qc

    def circuits(self) -> list[QuantumCircuit]:
        z_basis = self._ghz()
        z_basis.measure_all()
        z_basis.name = "ghz_z"
        x_basis = self._ghz()
        x_basis.h(range(self.n))
        x_basis.measure_all()
        x_basis.name = "ghz_x"
        return [z_basis, x_basis]

    def analyze(self, distributions: list[dict[str, float]]) -> dict:
        z, x = distributions
        population = z.get("0" * self.n, 0.0) + z.get("1" * self.n, 0.0)
        parity_x = sum(p * (-1) ** key.count("1") for key, p in x.items())
        return {
            "num_qubits": self.n,
            "population": population,
            "parity_x": parity_x,
            # (P + <X^n>) / 2 equals 1 for an ideal GHZ state; a standard quick estimator.
            "fidelity": (population + parity_x) / 2,
        }
