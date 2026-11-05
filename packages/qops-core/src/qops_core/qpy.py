"""QPY helpers: serialize circuits for snapshots (``circuits.qpy``) without losing parameters."""

from __future__ import annotations

import io
from collections.abc import Sequence

from qiskit import QuantumCircuit, qpy


def circuits_to_bytes(circuits: Sequence[QuantumCircuit]) -> bytes:
    buffer = io.BytesIO()
    qpy.dump(list(circuits), buffer)
    return buffer.getvalue()


def circuits_from_bytes(data: bytes) -> list[QuantumCircuit]:
    return list(qpy.load(io.BytesIO(data)))
