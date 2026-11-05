"""Run state snapshots: everything needed to resume a run in a fresh process (state hydration).

The snapshot is plain JSON (``state.json``) with a ``schema_version``. Loading a snapshot written
with a different major schema version fails loudly instead of resuming with wrong assumptions.
"""

from __future__ import annotations

import json
import os
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from qops_core.models import ExperimentKind

SCHEMA_VERSION = 1


class StateError(ValueError):
    """A snapshot cannot be loaded."""


@dataclass
class RunState:
    """A run's resumable state. ``optimizer`` and ``algorithm_state`` must stay JSON-serializable."""

    kind: ExperimentKind
    algorithm: str
    config: dict[str, Any]
    provider: str
    backend: str
    shots: int | None
    seed: int
    run_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    iteration: int = 0
    optimizer: dict[str, Any] = field(default_factory=dict)
    algorithm_state: dict[str, Any] = field(default_factory=dict)
    history: list[dict[str, Any]] = field(default_factory=list)
    finished: bool = False
    schema_version: int = SCHEMA_VERSION

    def to_json(self) -> str:
        data = asdict(self)
        data["kind"] = self.kind.value
        return json.dumps(data, indent=2, sort_keys=True, allow_nan=False)

    @classmethod
    def from_json(cls, text: str) -> RunState:
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise StateError(f"state is not valid JSON: {exc}") from exc
        version = data.get("schema_version")
        if version != SCHEMA_VERSION:
            raise StateError(
                f"state schema_version {version!r} is not supported (expected {SCHEMA_VERSION})"
            )
        data["kind"] = ExperimentKind(data["kind"])
        try:
            return cls(**data)
        except TypeError as exc:
            raise StateError(f"state has unexpected fields: {exc}") from exc


def save_state(state: RunState, path: str | Path) -> Path:
    """Atomically write ``state`` to ``path`` (write to a temp file, then rename)."""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(state.to_json() + "\n", encoding="utf-8")
    os.replace(tmp, target)
    return target


def load_state(path: str | Path) -> RunState:
    return RunState.from_json(Path(path).read_text(encoding="utf-8"))
