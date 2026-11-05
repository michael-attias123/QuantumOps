# Definition-of-Done checks, one target per phase (docs/ROADMAP.md).
ALGORITHMS := research/algorithms

.PHONY: verify-p0 verify-p1

verify-p0: sync lint test ## P0 Definition of Done checks
	$(UV) run qops --version
	@echo "P0 verified"

verify-p1: verify-p0 compat ## P1 Definition of Done checks
	$(UV) run pytest -q packages/qops-runtime/tests/test_local.py tests/test_algorithms.py tests/test_architecture.py
	$(UV) run qops run --local $(ALGORITHMS)/ghz_benchmark --state-dir .qops/verify/ghz
	$(UV) run qops run --local $(ALGORITHMS)/vqe_h2 --state-dir .qops/verify/vqe
	@echo "P1 verified"
