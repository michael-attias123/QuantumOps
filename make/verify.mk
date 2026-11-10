# Definition-of-Done checks, one target per phase (docs/ROADMAP.md).
ALGORITHMS := research/algorithms

.PHONY: verify-p0 verify-p1 verify-p2 verify-p3 verify-p4

verify-p0: sync lint test ## P0 Definition of Done checks
	$(UV) run qops --version
	@echo "P0 verified"

verify-p1: verify-p0 compat ## P1 Definition of Done checks
	$(UV) run pytest -q packages/qops-runtime/tests/test_local.py tests/test_algorithms.py tests/test_architecture.py
	$(UV) run qops run --local $(ALGORITHMS)/ghz_benchmark --state-dir .qops/verify/ghz
	$(UV) run qops run --local $(ALGORITHMS)/vqe_h2 --state-dir .qops/verify/vqe
	@echo "P1 verified"

verify-p2: verify-p1 infra-check ## P2 Definition of Done checks (needs the live cluster)
	$(TOFU_SH) plan -detailed-exitcode -lock=false
	$(NODE_SH) verify
	@echo "P2 verified"

verify-p3: verify-p2 deploy-check ## P3 Definition of Done checks (needs the live cluster)
	bash deploy/bootstrap/scripts/verify.sh
	@echo "P3 verified"

verify-p4: verify-p3 ## P4 Definition of Done checks (needs the live cluster and the shared Vault)
	$(ON_TAILNET) bash deploy/bootstrap/scripts/verify-p4.sh
	@echo "P4 verified"
