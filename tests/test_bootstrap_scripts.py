"""Drive the P2 bootstrap scripts (infra/bootstrap/) against stub `oci`, `tailscale` and `curl` commands.

The stubs log every call and answer from two canned states: ``fresh`` (a new tenancy, nothing created yet) and
``ready`` (everything already exists). This checks idempotency, dry-run behaviour and that secrets never reach stdout.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "infra" / "bootstrap"
SECRET = "s3cr3t-value-never-printed"
TS_TOKEN = "tskey-api-k123-abcdefghijklmnop"  # gitleaks:allow (fake, for tests)

OCI_STUB = r"""#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
args="$*"
ready() { [[ "$STUB_STATE" == "ready" ]]; }
case "$args" in
  *"iam region-subscription list"*) echo '{"data":[{"region-name":"eu-frankfurt-1"}]}' ;;
  *"limits value list"*standard-a1-core-count*) echo '{"data":[{"value":4},{"value":0}]}' ;;
  *"limits value list"*standard-a1-memory-count*) echo '{"data":[{"value":24}]}' ;;
  *"limits value list"*gpu-a10-count*) echo '{"data":[{"value":0}]}' ;;
  *"iam compartment get"*) echo '{"data":{"time-created":"2026-11-07T10:00:00.000Z"}}' ;;
  *"iam user get"*) echo '{"data":{"email":"me@example.com"}}' ;;
  *"budgets budget budget list"*)
    if ready; then echo '{"data":[{"display-name":"qops-always-free","id":"b1"}]}'
    else echo '{"data":[]}'; fi ;;
  *"budgets budget alert-rule list"*)
    echo '{"data":[{"display-name":"any-spend"},{"display-name":"credits-50"},{"display-name":"credits-150"},{"display-name":"credits-250"}]}' ;;
  *"os ns get"*) echo '{"data":"axnamespace"}' ;;
  *"os bucket get"*)
    if ready; then echo '{"data":{"versioning":"Enabled"}}'; else echo 'ServiceError: 404' >&2; exit 1; fi ;;
  *"customer-secret-key list"*)
    if ready; then echo '{"data":[{"display-name":"qops-tofu","id":"k1"}]}'; else echo '{"data":[]}'; fi ;;
  *"customer-secret-key create"*) echo "{\"data\":{\"id\":\"AKID123\",\"key\":\"$STUB_SECRET\"}}" ;;
  *"--version"*) echo "3.70.0" ;;
  *) echo '{}' ;;
esac
"""

TAILSCALE_STUB = r"""#!/usr/bin/env bash
case "$*" in
  "status --json") echo '{"BackendState":"Running","MagicDNSSuffix":"tail1234.ts.net","CertDomains":["pc.tail1234.ts.net"]}' ;;
  version) echo "1.90.0" ;;
esac
"""

CURL_STUB = r"""#!/usr/bin/env bash
cat > /dev/null
exit 0
"""


def _write_stub(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    if shutil.which("jq") is None or shutil.which("bash") is None:
        pytest.skip("bash and jq are required")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_stub(bin_dir, "oci", OCI_STUB)
    _write_stub(bin_dir, "tailscale", TAILSCALE_STUB)
    _write_stub(bin_dir, "curl", CURL_STUB)
    home = tmp_path / "home"
    (home / ".oci").mkdir(parents=True)
    (home / ".oci" / "config").write_text(
        "[DEFAULT]\nuser=ocid1.user.oc1..u\nfingerprint=aa\ntenancy=ocid1.tenancy.oc1..t\n"
        "region = eu-frankfurt-1\nkey_file=~/.oci/k.pem\n"
    )
    return {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "HOME": str(home),
        "STUB_LOG": str(tmp_path / "calls.log"),
        "STUB_STATE": "fresh",
        "STUB_SECRET": SECRET,
        "QOPS_CONFIG_DIR": str(home / ".config" / "qops"),
    }


def _run(script: str, *args: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPTS / script), *args],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _calls(env: dict[str, str]) -> str:
    log = Path(env["STUB_LOG"])
    return log.read_text() if log.exists() else ""


MUTATING = (" create ", " update ", " delete ")


def test_dry_run_on_fresh_tenancy_plans_everything_and_changes_nothing(env: dict[str, str]) -> None:
    result = _run("oci.sh", "all", "--dry-run", env=env)
    assert result.returncode == 0, result.stderr
    out = result.stderr
    # The bucket and the budget belong to shared-platform's oci-foundation: only checked, never created here.
    assert "budget create" not in out
    assert "alert-rule create" not in out
    assert "bucket create" not in out
    assert "budget qops-always-free is missing" in out
    assert "bucket qops-tofu-state is missing" in out
    assert out.count("make apply STACK=oci-foundation") == 2
    assert "customer-secret-key create" in out
    assert not any(verb in f" {line} " for line in _calls(env).splitlines() for verb in MUTATING)
    assert not (Path(env["QOPS_CONFIG_DIR"]) / "oci.env").exists()


def test_limits_warn_about_trial_limits_and_zero_gpu(env: dict[str, str]) -> None:
    result = _run("oci.sh", "limits", env=env)
    assert result.returncode == 0, result.stderr
    assert "Ampere A1: 4 OCPU / 24 GB" in result.stdout
    assert "Trial ends about: 2026-12-07" in result.stdout
    assert "trial limits" in result.stderr
    assert "GPU A10 limit is 0" in result.stderr


def test_secret_key_is_saved_privately_and_never_printed(env: dict[str, str]) -> None:
    result = _run("oci.sh", "secret-key", env=env)
    assert result.returncode == 0, result.stderr
    assert SECRET not in result.stdout + result.stderr
    env_file = Path(env["QOPS_CONFIG_DIR"]) / "oci.env"
    assert stat.S_IMODE(env_file.stat().st_mode) == 0o600
    content = env_file.read_text()
    assert f"AWS_SECRET_ACCESS_KEY={SECRET}" in content
    assert "AWS_ACCESS_KEY_ID=AKID123" in content
    assert "QOPS_OCI_NAMESPACE=axnamespace" in content


def test_rerun_when_ready_is_a_no_op(env: dict[str, str]) -> None:
    assert _run("oci.sh", "secret-key", env=env).returncode == 0
    env["STUB_STATE"] = "ready"
    Path(env["STUB_LOG"]).unlink()
    result = _run("oci.sh", "all", env=env)
    assert result.returncode == 0, result.stderr
    assert not any(verb in f" {line} " for line in _calls(env).splitlines() for verb in MUTATING)
    assert "bucket qops-tofu-state (versioned; owned by shared-platform)" in result.stdout
    assert "budget qops-always-free (4 alerts; owned by shared-platform)" in result.stdout


def test_existing_key_without_local_copy_refuses_without_rotate(env: dict[str, str]) -> None:
    env["STUB_STATE"] = "ready"
    result = _run("oci.sh", "secret-key", env=env)
    assert result.returncode == 1
    assert "--rotate-secret-key" in result.stderr


def test_missing_oci_config_points_to_login(env: dict[str, str]) -> None:
    Path(env["HOME"], ".oci", "config").unlink()
    result = _run("oci.sh", "all", env=env)
    assert result.returncode == 1
    assert "make oci-login" in result.stderr


def test_tailscale_check_reads_tailnet_and_https(env: dict[str, str]) -> None:
    cfg = Path(env["QOPS_CONFIG_DIR"])
    cfg.mkdir(parents=True)
    (cfg / "tailscale.env").write_text(f"TAILSCALE_API_KEY={TS_TOKEN}\n")
    result = _run("tailscale.sh", "check", env=env)
    assert result.returncode == 0, result.stderr
    assert "tailnet DNS name tail1234.ts.net" in result.stdout
    assert "HTTPS certificates on" in result.stdout
    assert "API token valid" in result.stdout
    assert TS_TOKEN not in result.stdout + result.stderr


def test_report_lists_values_and_hides_secrets(env: dict[str, str]) -> None:
    assert _run("oci.sh", "secret-key", env=env).returncode == 0
    (Path(env["QOPS_CONFIG_DIR"]) / "tailscale.env").write_text(f"TAILSCALE_API_KEY={TS_TOKEN}\n")
    env["STUB_STATE"] = "ready"
    result = _run("report.sh", env=env)
    assert result.returncode == 0, result.stderr
    out = result.stdout
    for expected in (
        "OCI home region:            eu-frankfurt-1",
        "Ampere A1 limits:           4 OCPU / 24 GB",
        "GPU A10 limit:              0",
        "Trial end date:             2026-12-07 (estimate)",
        "Object Storage namespace:   axnamespace",
        "Tailnet DNS name:           tail1234.ts.net",
        "[x] budget alerts (4/4)",
        "[x] bucket versioned",
        "[x] S3 key saved",
        "[x] Tailscale token saved",
        "[x] HTTPS certificates",
    ):
        assert expected in out
    assert SECRET not in out
    assert TS_TOKEN not in out
    assert "AKID123" not in out


def test_report_without_any_setup_still_succeeds(env: dict[str, str]) -> None:
    Path(env["HOME"], ".oci", "config").unlink()
    result = _run("report.sh", env=env)
    assert result.returncode == 0, result.stderr
    assert "OCI home region:            ?" in result.stdout
    assert "[ ] OCI API login works" in result.stdout
