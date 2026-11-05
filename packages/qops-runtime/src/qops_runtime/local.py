"""In-process runtime: the full L1 → L2 → L3 loop in one process (``qops run --local``).

The cluster runtime (P6+) runs the same steps in separate pods. This module keeps the same
boundaries: every iteration ends with a state snapshot, so a run can stop at any step and resume
from ``state.json`` with an identical trajectory.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from qiskit import QuantumCircuit
from qiskit.transpiler import generate_preset_pass_manager

from qops_core.contract import LoadedAlgorithm, load_algorithm
from qops_core.models import ExperimentKind, ResultSet
from qops_core.state import RunState, load_state, save_state
from qops_providers import JobSpec, QuantumProvider, get_provider
from qops_stages import energy, group_observable, make_optimizer, measurement_circuit
from qops_stages.optimizers import restore_optimizer

STATE_FILE = "state.json"
ProgressCallback = Callable[[dict[str, Any]], None]


@dataclass
class LocalRunOptions:
    provider: str = "aer"
    backend: str = "exact"
    shots: int | None = None
    seed: int = 7
    maxiter: int = 150
    optimizer: str = "spsa"
    config: dict[str, Any] = field(default_factory=dict)
    state_dir: Path | None = None
    max_steps: int | None = None  # stop after this many iterations in this process (resumable)


@dataclass
class RunReport:
    run_id: str
    kind: ExperimentKind
    algorithm: str
    finished: bool
    iterations: int
    result: dict[str, Any]
    state_path: Path | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "kind": self.kind.value,
            "algorithm": self.algorithm,
            "finished": self.finished,
            "iterations": self.iterations,
            "result": self.result,
            "state_path": str(self.state_path) if self.state_path else None,
        }


def _execute(
    provider: QuantumProvider, circuits: list[QuantumCircuit], state: RunState, step: int
) -> ResultSet:
    """L1 submit → L2 run → fetch. Seeds derive from (run seed, step) for reproducibility."""
    job = JobSpec(
        circuits=circuits,
        backend=state.backend,
        shots=state.shots,
        seed=state.seed * 1_000_003 + step,
    )
    ref = provider.submit(job)
    return provider.result(ref)


def _transpile(
    provider: QuantumProvider, backend: str, circuits: list[QuantumCircuit]
) -> list[QuantumCircuit]:
    pass_manager = generate_preset_pass_manager(
        optimization_level=1, target=provider.target(backend), seed_transpiler=0
    )
    return list(pass_manager.run(circuits))


def _snapshot(state: RunState, state_dir: Path | None) -> Path | None:
    if state_dir is None:
        return None
    return save_state(state, state_dir / STATE_FILE)


def _run_sampling(
    algorithm: LoadedAlgorithm, provider: QuantumProvider, state: RunState
) -> dict[str, Any]:
    circuits = algorithm.call("circuits")
    results = _execute(provider, _transpile(provider, state.backend, circuits), state, step=0)
    distributions = results.distributions()
    analysis: dict[str, Any] = (
        dict(algorithm.call("analyze", distributions)) if algorithm.has("analyze") else {}
    )
    return {"analysis": analysis, "distributions": distributions}


def _run_variational(
    algorithm: LoadedAlgorithm,
    provider: QuantumProvider,
    state: RunState,
    options: LocalRunOptions,
    progress: ProgressCallback | None,
) -> dict[str, Any]:
    ansatz: QuantumCircuit = algorithm.call("ansatz")
    groups = group_observable(algorithm.call("hamiltonian"))
    # Parameterized measurement circuits are transpiled once and bound every iteration.
    templates = _transpile(
        provider, state.backend, [measurement_circuit(ansatz, g) for g in groups]
    )
    parameters = list(ansatz.parameters)

    def evaluate(points: list[list[float]], step: int) -> list[float]:
        bound = [
            t.assign_parameters(dict(zip(parameters, point, strict=True)))
            for point in points
            for t in templates
        ]
        distributions = _execute(provider, bound, state, step).distributions()
        n = len(templates)
        return [energy(groups, distributions[i * n : (i + 1) * n]) for i in range(len(points))]

    if state.optimizer:
        optimizer = restore_optimizer(state.optimizer)
    else:
        optimizer = make_optimizer(
            options.optimizer,
            list(algorithm.call("initial_point")),
            maxiter=options.maxiter,
            seed=state.seed,
        )
        state.optimizer = optimizer.to_state()

    steps_this_process = 0
    while not optimizer.done:
        if options.max_steps is not None and steps_this_process >= options.max_steps:
            return {"stopped_early": True}
        points = optimizer.ask()  # L1: next parameter points
        values = evaluate(points, step=state.iteration)  # L2: one job per iteration
        optimizer.tell(values)  # L3: optimizer step
        state.iteration += 1
        record = {"iteration": state.iteration, "value": 0.5 * (values[0] + values[1])}
        state.history.append(record)
        state.optimizer = optimizer.to_state()
        _snapshot(state, options.state_dir)
        steps_this_process += 1
        if progress:
            progress(record)

    final_value = evaluate([optimizer.x], step=state.iteration)[0]
    result: dict[str, Any] = {
        "energy": final_value,
        "parameters": optimizer.x,
        "best_estimate": optimizer.best_value,
    }
    if algorithm.has("exact_value"):
        exact = float(algorithm.call("exact_value"))
        result["exact"] = exact
        result["error"] = final_value - exact
    return result


def run_local(
    algorithm_path: str | Path | None = None,
    options: LocalRunOptions | None = None,
    resume: str | Path | None = None,
    progress: ProgressCallback | None = None,
) -> RunReport:
    """Run an algorithm in-process, or resume one from a ``state.json`` snapshot."""
    options = options or LocalRunOptions()
    if resume is not None:
        resume_path = Path(resume)
        state = load_state(resume_path)
        if options.state_dir is None:
            options.state_dir = resume_path.parent
        algorithm = load_algorithm(state.algorithm, state.config)
    else:
        if algorithm_path is None:
            raise ValueError("algorithm_path or resume is required")
        algorithm = load_algorithm(algorithm_path, options.config)
        state = RunState(
            kind=algorithm.kind,
            algorithm=str(Path(algorithm_path)),
            config=algorithm.config,
            provider=options.provider,
            backend=options.backend,
            shots=options.shots,
            seed=options.seed,
        )
    provider = get_provider(state.provider)

    if state.kind is ExperimentKind.SAMPLING:
        result = _run_sampling(algorithm, provider, state)
        state.iteration = 1
        state.finished = True
    elif state.kind is ExperimentKind.VARIATIONAL:
        result = _run_variational(algorithm, provider, state, options, progress)
        state.finished = not result.get("stopped_early", False)
    else:
        raise NotImplementedError(f"kind '{state.kind}' runs from P10 (QEC experiments)")

    if state.finished:
        state.algorithm_state = {"result": result}
    path = _snapshot(state, options.state_dir)
    return RunReport(
        run_id=state.run_id,
        kind=state.kind,
        algorithm=algorithm.metadata.name,
        finished=state.finished,
        iterations=state.iteration,
        result=result,
        state_path=path,
    )
