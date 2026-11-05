import pytest
from qiskit import QuantumCircuit

from qops_providers import JobSpec, JobStatus, ProviderError, available_providers, get_provider
from qops_providers.aer import AerProvider, exact_distribution


def bell() -> QuantumCircuit:
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    qc.measure_all()
    return qc


def test_registry() -> None:
    assert "aer" in available_providers()
    assert isinstance(get_provider("aer"), AerProvider)
    with pytest.raises(ProviderError, match="unknown provider"):
        get_provider("does-not-exist")


def test_exact_probabilities() -> None:
    provider = AerProvider()
    ref = provider.submit(JobSpec(circuits=[bell()], backend="exact", shots=None))
    assert provider.status(ref) is JobStatus.DONE
    (result,) = provider.result(ref).results
    assert result.shots is None
    assert result.probabilities == pytest.approx({"00": 0.5, "11": 0.5})


def test_exact_respects_clbit_order() -> None:
    qc = QuantumCircuit(2, 2)
    qc.x(0)
    qc.measure(0, 1)  # qubit 0 -> clbit 1 (leftmost bit)
    qc.measure(1, 0)
    assert exact_distribution(qc) == pytest.approx({"10": 1.0})


def test_seeded_sampling_is_reproducible() -> None:
    provider = AerProvider()
    job = JobSpec(circuits=[bell()], backend="sampler", shots=1000, seed=11)
    first = provider.result(provider.submit(job)).results[0]
    second = provider.result(provider.submit(job)).results[0]
    assert first.counts == second.counts
    assert first.shots == 1000
    assert set(first.probabilities) <= {"00", "11"}


def test_validation_and_cost() -> None:
    provider = AerProvider()
    with pytest.raises(ProviderError, match="exact probabilities not supported"):
        provider.submit(JobSpec(circuits=[bell()], backend="sampler", shots=None))
    with pytest.raises(ProviderError, match="unknown backend"):
        provider.submit(JobSpec(circuits=[bell()], backend="ibm_torino", shots=10))
    with pytest.raises(ProviderError, match="circuits per job"):
        provider.submit(JobSpec(circuits=[], backend="exact", shots=None))
    assert provider.estimate_cost(JobSpec(circuits=[bell()], backend="exact", shots=None)).is_free
    assert not provider.capabilities("exact").paid
