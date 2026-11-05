from qiskit import QuantumCircuit
from qiskit.circuit import Parameter

from qops_core.qpy import circuits_from_bytes, circuits_to_bytes


def test_qpy_roundtrip_keeps_parameters() -> None:
    theta = Parameter("theta")
    qc = QuantumCircuit(2, name="param")
    qc.ry(theta, 0)
    qc.cx(0, 1)
    qc.measure_all()
    (loaded,) = circuits_from_bytes(circuits_to_bytes([qc]))
    assert loaded == qc
    assert [p.name for p in loaded.parameters] == ["theta"]
