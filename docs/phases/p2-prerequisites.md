# Before P2: what to do, and what to bring

P2 builds the always-on cluster: **k3s on Oracle Cloud Always Free ARM (Ampere A1)**, with no public ports, reachable
from your computers over **Tailscale**. I write all the code; **you** run it from your computer, so your cloud keys never
leave your machine.

Most of the setup is scripted (`infra/bootstrap/`, `make` targets below). What remains by hand needs a human: sign-ups,
browser logins and one token. It takes about **15 minutes**, and you never copy a secret by hand: the scripts write
secrets straight into `~/.config/qops/*.env` (mode 600, outside the repo).

Everything is **free**. Three rules:
- **Never press *Upgrade* / "Pay As You Go"** in Oracle without asking me first.
- **Never paste secrets in chat**: private keys, secret keys, tokens, or the contents of `~/.oci/config` or `~/.config/qops/`.
- **Don't create Ampere A1 machines by hand.** More than 2 OCPU / 12 GB of A1 when the Free Trial ends deletes *all*
  of them ([ADR 0010](../adr/0010-oci-trial-burst-layer.md)).

---

## Step 1 — By hand (about 10 minutes)

| # | What | Where | Notes |
|---|---|---|---|
| 1 | Oracle Cloud sign-up | cloud.oracle.com → *Start for free* | ✅ Done. The home region is permanent; Always Free ARM exists only there. |
| 2 | Tailscale sign-up | login.tailscale.com | The free Personal plan is enough. |
| 3 | Tailscale **HTTPS certificates** on | [admin → DNS](https://login.tailscale.com/admin/dns) → *Enable HTTPS* | Keep MagicDNS on. There's no API for this toggle. P3 uses it for the web UIs. |
| 4 | Tailscale **API access token** | [admin → Settings → Keys](https://login.tailscale.com/admin/settings/keys) → *Generate access token* | Description `qops-tofu`, expiry 90 days. Don't copy it anywhere yet; step 2 asks for it in a hidden prompt. |
| 5 | Windows only: **WSL2** | PowerShell (admin): `wsl --install` | Then work inside Ubuntu. Install Tailscale on **Windows** itself; WSL shares its connection. |

## Step 2 — Scripted

On the **admin computer** (the one that will run OpenTofu), from the repo root:

```bash
make tools-admin
```
It installs anything missing (git, make, jq, uv, kubectl, Tailscale, OpenTofu ≥ 1.10, OCI CLI) and creates the SSH
break-glass key `~/.ssh/qops_oci`. Open a new shell afterwards if it installed uv.

```bash
sudo tailscale up
```
A browser login, once per computer.

```bash
make oci-login
```
A browser login to Oracle. It creates the API key pair and `~/.oci/config` for you. When asked, choose your
**home region** and profile `DEFAULT`; you can skip the passphrase.

```bash
make oci-bootstrap
```
It does the following, and is safe to rerun:
- prints your **Ampere A1** and **GPU A10** limits and the estimated **trial end date**;
- creates the budgets: **$1** (alert at 1%) and **$300 trial credits** (alerts at $50 / $150 / $250), emailed to you;
- creates the versioned state bucket **`qops-tofu-state`**;
- creates the S3-compatible key → `~/.config/qops/oci.env`.

```bash
make tailscale-login
```
Paste the token from step 1.4 into the **hidden** prompt. The script also checks the tailnet name and that HTTPS
certificates are on.

```bash
make prereqs-report
```
It prints everything I need, with no secrets.

On every **other computer**, run `make tools`, then `sudo tailscale up` (or the Tailscale app on Windows/macOS).
Then `make tailscale-check`.

Each command takes `ARGS=--dry-run` to show what it would do without changing anything, for example
`make oci-bootstrap ARGS=--dry-run`.

### If the GPU A10 limit is 0
This is common on trial accounts, and optional (ADR 0010). `make oci-bootstrap` prints the link:
*Limits, Quotas and Usage* → **Request a service limit update** → Compute → GPU A10 → **1**, in your home region.
Approval can take days, so file it early. If Oracle refuses, we skip the trial GPU test.

### Trial end date
The script estimates it from the tenancy's creation date. Confirm it once under *Billing & Cost Management →
Subscriptions*. Everything bought with trial credits is deleted by **day 27**.

---

## What to bring me
Paste the whole output of `make prereqs-report`. It looks like this:

```text
--- QuantumOps P2 prerequisites (no secrets) ---
OCI home region:            eu-frankfurt-1
Ampere A1 limits:           4 OCPU / 24 GB
GPU A10 limit:              0
Trial end date:             2026-12-07 (estimate)
Object Storage namespace:   axq1bcdefg2h
State bucket:               qops-tofu-state
Tailnet DNS name:           tail1234ab.ts.net
This computer's OS:         Ubuntu 24.04.1 LTS (WSL2) (x86_64)
Checklist:                  [x] OCI API login works  [x] budgets (2/2)  [x] bucket versioned
                            [x] S3 key saved  [x] Tailscale token saved
                            [x] on the tailnet  [x] HTTPS certificates  [x] SSH key
Tools:                      tofu 1.10.x …
---
```
Also tell me the OS of your other computers, the confirmed trial end date, and whether a GPU request is pending.
If any line shows `?` or `[ ]`, paste the error from the matching `make` command (check it contains no keys).

## How P2 will work between us
1. I write `infra/oci/`, a single OpenTofu stack:
   - Oracle: network with no public inbound, 1 ARM VM (2 OCPU / 12 GB), cloud-init with k3s + Tailscale, KMS key,
     state in your bucket.
   - Tailscale, through the API token: the tailnet policy (tags) and MagicDNS, managed from Git; a **1-hour, tagged
     auth key** generated during `apply` and passed to the VM, so you never make one.

   It comes with `make infra-plan`, `make infra-apply` and `make kubeconfig`, which read `~/.config/qops/*.env`
   automatically. CI checks the code (`tofu fmt`, `tofu validate`, `tofu test` with mocked providers) without your
   credentials.
2. You run `make infra-plan`, then `make infra-apply`.
3. You paste the **non-secret** results: the plan summary line, `kubectl get nodes -o wide`, and any error. I fix
   anything that fails, and we repeat until the P2 Definition of Done is met.
4. Trial extras (`infra/oci-trial/`, `make trial-*`) are separate and optional; they never touch the permanent node.

---

## Appendix — manual fallback
Use this only if a script fails and we can't fix it quickly. Each item does by hand what one script step does.

- **API key** (`oci-login`): *Profile → My profile → API keys → Add API key → Generate API key pair*. Download the
  private key, then *Add*. Paste the "Configuration file preview" into `~/.oci/config` with
  `key_file=~/.oci/qops_api_key.pem`, then `chmod 600 ~/.oci/config ~/.oci/qops_api_key.pem`.
- **Limits** (`oci-bootstrap`): *Governance & Administration → Limits, Quotas and Usage*, filtered for "Ampere A1"
  and "GPU A10". During the trial the A1 numbers are trial limits; we still build for 2 OCPU / 12 GB.
- **Budgets:** *Billing & Cost Management → Budgets → Create budget*, root compartment.
  - `qops-always-free`: $1, alert at 1% of actual spend.
  - `qops-trial-credits`: $300, alerts at $50, $150 and $250 (absolute, actual).
- **Bucket:** *Storage → Buckets → Create bucket* `qops-tofu-state`, Standard tier, Object Versioning on. Note the
  namespace.
- **S3 key:** *My profile → Customer secret keys → Generate secret key* `qops-tofu`. Put it in `~/.config/qops/oci.env`
  as `AWS_ACCESS_KEY_ID=` / `AWS_SECRET_ACCESS_KEY=` and `chmod 600` the file.
- **Tailscale token** (`tailscale-login`): write `TAILSCALE_API_KEY=tskey-api-…` to `~/.config/qops/tailscale.env`
  and `chmod 600` it.
- **SSH key:** `ssh-keygen -t ed25519 -f ~/.ssh/qops_oci -C qops-oci`.
