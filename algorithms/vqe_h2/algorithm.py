"""VQE for H2 (2-qubit parity-reduced, STO-3G, bond length 0.735 Å). Pure Qiskit."""

from qiskit import QuantumCircuit
from qiskit.circuit.library import real_amplitudes
from qiskit.quantum_info import SparsePauliOp

# Electronic Hamiltonian coefficients (Ha). Nuclear repulsion 0.7199689944 Ha is not included.
H2_TERMS = [
    ("II", -1.052373245772859),
    ("IZ", 0.39793742484318045),
    ("ZI", -0.39793742484318045),
    ("ZZ", -0.01128010425623538),
    ("XX", 0.18093119978423156),
]


class Algorithm:
    def __init__(self, config: dict) -> None:
        self.reps = int(config.get("reps", 2))

    def ansatz(self) -> QuantumCircuit:
        return real_amplitudes(2, reps=self.reps)

    def hamiltonian(self) -> SparsePauliOp:
        return SparsePauliOp.from_list(H2_TERMS)

    def initial_point(self) -> list[float]:
        return [0.1] * self.ansatz().num_parameters

    def exact_value(self) -> float:
        return -1.8572750302023795  # lowest eigenvalue of hamiltonian()
