"""Ask/tell optimizers with JSON-serializable state.

The variational loop is split across processes (L1 asks, L3 tells), so an optimizer must be fully
described by ``to_state()`` and rebuilt with ``from_state()``, including its random generator.
Resuming from a snapshot therefore reproduces the uninterrupted trajectory exactly.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

import numpy as np
from numpy.typing import NDArray

FloatArray = NDArray[np.float64]


@dataclass
class SPSA:
    """Simultaneous Perturbation Stochastic Approximation (Spall), with optional calibration.

    Each step needs two objective evaluations (``x + c_k Δ`` and ``x - c_k Δ``), which are
    submitted together as one job. ``a = None`` triggers Spall's calibration on the first step:
    ``a`` is chosen so the first update moves each parameter by about ``target_magnitude``.
    """

    x: list[float]
    maxiter: int = 100
    a: float | None = None
    c: float = 0.1
    alpha: float = 0.602
    gamma: float = 0.101
    stability: float | None = None
    target_magnitude: float = 0.2
    seed: int = 0
    k: int = 0
    pending: list[float] | None = None
    best_x: list[float] | None = None
    best_value: float | None = None
    rng_state: dict[str, Any] | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        self._rng = np.random.default_rng(self.seed)
        if self.rng_state is not None:
            self._rng.bit_generator.state = self.rng_state
        if self.stability is None:
            self.stability = 0.1 * self.maxiter

    @property
    def done(self) -> bool:
        return self.k >= self.maxiter

    def _ck(self) -> float:
        return float(self.c / (self.k + 1) ** self.gamma)

    def _ak(self) -> float:
        assert self.a is not None
        assert self.stability is not None
        return float(self.a / (self.k + 1 + self.stability) ** self.alpha)

    def ask(self) -> list[list[float]]:
        """Return the two parameter points to evaluate for the current step."""
        if self.done:
            raise RuntimeError("optimizer finished")
        if self.pending is None:
            self.pending = [float(v) for v in self._rng.choice([-1.0, 1.0], size=len(self.x))]
        delta = np.asarray(self.pending)
        x = np.asarray(self.x)
        ck = self._ck()
        return [list(map(float, x + ck * delta)), list(map(float, x - ck * delta))]

    def tell(self, values: list[float]) -> None:
        """Consume objective values for the points returned by ``ask``."""
        if self.pending is None:
            raise RuntimeError("tell() called without a pending ask()")
        if len(values) != 2:
            raise ValueError("SPSA expects exactly two values per step")
        plus, minus = values
        delta = np.asarray(self.pending)
        x = np.asarray(self.x)
        diff = (plus - minus) / (2.0 * self._ck())
        gradient = diff * delta  # delta entries are ±1, so 1/delta == delta
        if self.a is None:
            magnitude = abs(diff) if diff != 0 else 1.0
            self.a = self.target_magnitude * (1 + self.stability) ** self.alpha / magnitude  # type: ignore[operator]
        x = x - self._ak() * gradient
        self.x = list(map(float, x))
        estimate = 0.5 * (plus + minus)
        if self.best_value is None or estimate < self.best_value:
            self.best_value = float(estimate)
            self.best_x = self.x
        self.k += 1
        self.pending = None

    def to_state(self) -> dict[str, Any]:
        state = {
            "name": "spsa",
            "x": self.x,
            "maxiter": self.maxiter,
            "a": self.a,
            "c": self.c,
            "alpha": self.alpha,
            "gamma": self.gamma,
            "stability": self.stability,
            "target_magnitude": self.target_magnitude,
            "seed": self.seed,
            "k": self.k,
            "pending": self.pending,
            "best_x": self.best_x,
            "best_value": self.best_value,
            "rng_state": self._rng.bit_generator.state,
        }
        for key in ("a", "best_value"):
            value = state[key]
            if isinstance(value, float) and not math.isfinite(value):
                raise ValueError(f"SPSA state field {key} is not finite")
        return state

    @classmethod
    def from_state(cls, state: dict[str, Any]) -> SPSA:
        data = dict(state)
        name = data.pop("name", "spsa")
        if name != "spsa":
            raise ValueError(f"not an SPSA state: {name}")
        return cls(**data)


def make_optimizer(name: str, x0: list[float], **options: Any) -> SPSA:
    if name != "spsa":
        raise ValueError(f"unknown optimizer '{name}' (available: spsa)")
    return SPSA(x=list(map(float, x0)), **options)


def restore_optimizer(state: dict[str, Any]) -> SPSA:
    name = state.get("name")
    if name != "spsa":
        raise ValueError(f"unknown optimizer '{name}' (available: spsa)")
    return SPSA.from_state(state)
