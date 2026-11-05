"""L3 stage plugins: error mitigation, QEC decoders, ask/tell optimizers."""

from qops_stages.measurement import (
    MeasurementGroup,
    energy,
    expectation_from_distribution,
    group_observable,
    measurement_circuit,
)
from qops_stages.optimizers import SPSA, make_optimizer, restore_optimizer

__version__ = "0.0.1"

__all__ = [
    "SPSA",
    "MeasurementGroup",
    "__version__",
    "energy",
    "expectation_from_distribution",
    "group_observable",
    "make_optimizer",
    "measurement_circuit",
    "restore_optimizer",
]
