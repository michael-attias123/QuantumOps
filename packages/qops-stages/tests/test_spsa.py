import json

import numpy as np
import pytest

from qops_stages.optimizers import SPSA, make_optimizer, restore_optimizer


def quadratic(x: list[float]) -> float:
    return float(np.sum((np.asarray(x) - 1.5) ** 2))


def run(opt: SPSA, steps: int) -> None:
    for _ in range(steps):
        opt.tell([quadratic(p) for p in opt.ask()])


def test_converges_on_quadratic() -> None:
    opt = make_optimizer("spsa", [0.0, 0.0, 0.0], maxiter=300, seed=3)
    run(opt, 300)
    assert opt.done
    assert quadratic(opt.x) < 1e-3


def test_state_roundtrip_reproduces_trajectory() -> None:
    straight = make_optimizer("spsa", [0.0, 0.0], maxiter=50, seed=5)
    run(straight, 50)

    resumed = make_optimizer("spsa", [0.0, 0.0], maxiter=50, seed=5)
    run(resumed, 20)
    resumed.ask()  # an ask in flight must survive the snapshot too
    resumed = restore_optimizer(json.loads(json.dumps(resumed.to_state())))
    run(resumed, 30)
    assert resumed.x == straight.x
    assert resumed.best_value == straight.best_value


def test_protocol_errors() -> None:
    opt = make_optimizer("spsa", [0.0], maxiter=1)
    with pytest.raises(RuntimeError, match="without a pending"):
        opt.tell([1.0, 2.0])
    opt.ask()
    with pytest.raises(ValueError, match="exactly two"):
        opt.tell([1.0])
    opt.tell([1.0, 2.0])
    with pytest.raises(RuntimeError, match="finished"):
        opt.ask()
    with pytest.raises(ValueError, match="unknown optimizer"):
        make_optimizer("adam", [0.0])
    with pytest.raises(ValueError, match="unknown optimizer"):
        restore_optimizer({"name": "adam"})
