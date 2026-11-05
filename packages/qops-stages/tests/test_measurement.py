import numpy as np
import pytest
from qiskit.circuit.library import real_amplitudes
from qiskit.quantum_info import SparsePauliOp, Statevector

from qops_providers.aer import exact_distribution
from qops_stages.measurement import energy, group_observable, measurement_circuit

OBSERVABLES = [
    SparsePauliOp.from_list(
        [("II", -1.05), ("IZ", 0.39), ("ZI", -0.39), ("ZZ", -0.01), ("XX", 0.18)]
    ),
    SparsePauliOp.from_list([("XYZ", 0.7), ("ZZI", -0.3), ("YIX", 0.25), ("III", 0.1)]),
]


@pytest.mark.parametrize("observable", OBSERVABLES)
def test_energy_matches_exact_expectation(observable: SparsePauliOp) -> None:
    n = observable.num_qubits
    ansatz = real_amplitudes(n, reps=2)
    rng = np.random.default_rng(0)
    for _ in range(3):
        bound = ansatz.assign_parameters(rng.uniform(-np.pi, np.pi, ansatz.num_parameters))
        groups = group_observable(observable)
        distributions = [exact_distribution(measurement_circuit(bound, g)) for g in groups]
        expected = Statevector(bound).expectation_value(observable).real
        assert energy(groups, distributions) == pytest.approx(expected, abs=1e-10)


def test_grouping_is_qubit_wise() -> None:
    groups = group_observable(OBSERVABLES[0])
    bases = {g.basis for g in groups}
    assert ("X", "X") in bases
    assert ("Z", "Z") in bases or ("Z", "I") in bases
    assert sum(len(g.observable) for g in groups) == len(OBSERVABLES[0])


def test_energy_requires_matching_lengths() -> None:
    groups = group_observable(OBSERVABLES[0])
    with pytest.raises(ValueError, match="one distribution per"):
        energy(groups, [])
