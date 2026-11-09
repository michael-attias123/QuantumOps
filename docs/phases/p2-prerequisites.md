# Before P2: what to do, and what to bring

P2 builds the always-on cluster: **k3s on Oracle Cloud Always Free ARM (Ampere A1)**, with no public ports, reachable
from your computers over **Tailscale**. I write all the OpenTofu code; **you** run it from your computer, so your cloud keys
never leave your machine. This page lists the one-time setup (about 45 minutes) and the few non-secret values to send me.

Everything here is **free**. Two rules:
- **Do not upgrade Oracle to "Pay As You Go"** without asking me first. Always Free doesn't need it.
- **Never paste secrets in chat**: private keys, secret keys, auth keys or the contents of `~/.oci/config`.

---

## 1. Tools on your computer(s)
Pick **one "admin" computer** to run OpenTofu from. Other computers only need Tailscale, kubectl, git and uv.
On Windows, use **WSL2** (Ubuntu).

| Tool | Admin computer | Other computers | Check |
|---|---|---|---|
| git, make | ✅ | ✅ | `git --version` |
| [uv](https://docs.astral.sh/uv/getting-started/installation/) | ✅ | ✅ | `uv --version` |
| [Tailscale](https://tailscale.com/download) | ✅ | ✅ | `tailscale version` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ✅ | ✅ | `kubectl version --client` |
| [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.10 (state locking in the shared S3 bucket) | ✅ | — | `tofu version` |
| [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (optional, helps with debugging) | optional | — | `oci --version` |

## 2. Oracle Cloud (OCI) account
1. Sign up at **cloud.oracle.com** → "Start for free".
   - **Home region: choose carefully, it can never be changed.** Always Free ARM machines exist only in your home
     region. Pick one near you. Popular regions sometimes run out of free ARM capacity; P2 handles that with
     retries, so don't worry too much.
   - A card is requested **for identity verification only**. Always Free resources are never charged.
   - **Write down the trial end date** (sign-up date + 30 days). See [section 2a](#2a-the-300--30-day-free-trial).
   - **Check your free ARM allowance:** *Governance & Administration → Limits, Quotas and Usage*, filter for
     "Ampere A1". Public reports say Oracle cut it in mid-2026 from 4 OCPU / 24 GB to **2 OCPU / 12 GB**
     ([InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)). Send me the numbers your console
     shows, because they set the cluster size. During the Free Trial the console may show the higher *trial* limits.
     We still build for 2 OCPU / 12 GB.
2. **Budget alarm** (safety net): *Billing & Cost Management → Budgets → Create budget*. Use the root
   compartment, amount **$1**, and an alert rule at **1% of actual spend** to your email. You'll hear about any
   cent spent. Spending trial credits sets this off too; that's expected during the trial (see 2a).
3. **API key** (lets OpenTofu manage resources):
   - *Profile icon (top right) → My profile → API keys → Add API key → Generate API key pair*.
   - **Download the private key**, then press *Add*.
   - Copy the "Configuration file preview" into `~/.oci/config` on the admin computer, and set `key_file=` to where
     you saved the private key (e.g. `~/.oci/qops_api_key.pem`).
   - `chmod 600 ~/.oci/config ~/.oci/qops_api_key.pem`.
   - Test (if you installed the OCI CLI): `oci iam region list` returns a list.
4. **Bucket for OpenTofu state**, so any computer sees the same infrastructure state:
   - *Storage → Buckets → Create bucket*, name **`qops-tofu-state`**, Standard tier, **enable Object Versioning**.
   - Note the **Object Storage namespace** shown on the bucket page (a short random-looking string). The S3-compatible
     endpoint will be `https://<namespace>.compat.objectstorage.<region>.oci.customer-oci.com`; Oracle is deprecating
     the older `…oraclecloud.com` form.
5. **S3-compatible key for that bucket**: *Profile → My profile → Customer secret keys → Generate secret key*.
   Name it `qops-tofu`, then **copy the secret immediately** (it's shown once) and the Access Key.
   Store both in your password manager. In P2 they go into environment variables on the admin computer only.

## 2a. The $300 / 30-day Free Trial
New accounts get $300 of credits for 30 days. We use them as a disposable extra
([ADR 0010](../adr/0010-oci-trial-burst-layer.md)): mainly a short GPU test for the error-correction layer. Everything
bought with credits is deleted by **day 27**.
1. **Never press *Upgrade*.** Credits and Always Free both work without it.
2. **The ARM trap:** if you have more than **2 OCPU / 12 GB of Ampere A1** when the trial ends, Oracle disables and later
   deletes *all* your A1 machines, including our cluster node. Don't create A1 machines by hand. The P2 code refuses
   anything bigger.
3. **GPU limit:** *Limits, Quotas and Usage*, filter for **"GPU A10"** (service *Compute*). If it's **0**, click
   *Request a service limit update* and ask for **1** `VM.GPU.A10.1` in your home region. Approval can take days, so
   do this first. If Oracle says no, we skip the GPU test.
4. **Credit alerts:** a second budget, amount **$300**, with alert rules at **$50, $150 and $250** of actual spend.

## 3. Tailscale
1. Sign up at **login.tailscale.com** (GitHub or Google login is fine). The free Personal plan is enough.
2. Install Tailscale on **every computer you work from** and run `tailscale up`. They should all appear under *Machines*.
3. *DNS* page: keep **MagicDNS** on, and enable **HTTPS Certificates** (P3 uses them for the web UIs).
   Note the **Tailnet DNS name** at the top, like `tail1234ab.ts.net`.
4. *Access controls*: add these tags to the policy file (inside the top-level `{ … }`), then save:
   ```jsonc
   "tagOwners": {
     "tag:qops-node":    ["autogroup:admin"],   // cluster VMs (P2)
     "tag:k8s-operator": [],                    // Tailscale Kubernetes operator (P3)
     "tag:k8s":          ["tag:k8s-operator"],  // services the operator exposes (P3)
   },
   ```
   If your policy already has a `tagOwners` block, add the three lines to it.
5. **Don't create the auth key yet.** Create it right before running P2 (it should expire soon after). Settings for later:
   *Settings → Keys → Generate auth key*: Reusable ✅ · Ephemeral ❌ · Pre-approved ✅ (matters only if device approval is on) · Tags `tag:qops-node` · Expiry 1 day.
   Tagged devices have key expiry disabled, so the nodes stay connected after the auth key expires.

## 4. SSH key (break-glass only)
Daily access goes through Tailscale SSH; this key is only for Oracle's emergency console access.
```bash
ssh-keygen -t ed25519 -f ~/.ssh/qops_oci -C qops-oci
```
The **public** key (`~/.ssh/qops_oci.pub`) goes into a local, git-ignored settings file in P2.

---

## What to bring me (paste in chat; none of this is secret)

```text
OCI home region:            e.g. eu-frankfurt-1
Ampere A1 limits (console): e.g. 2 OCPU / 12 GB
Trial end date:             e.g. 2026-12-07
GPU A10 limit:              e.g. 0 (request filed) / 1
Object Storage namespace:   e.g. axq1bcdefg2h
State bucket name:          qops-tofu-state (or yours)
Tailnet DNS name:           e.g. tail1234ab.ts.net
Admin computer OS:          e.g. Ubuntu 24.04 / macOS 15 / Windows 11 + WSL2
Other computers' OS:        …
Checklist:                  [ ] budget alarm  [ ] credit alerts $50/$150/$250  [ ] ~/.oci/config works  [ ] bucket + versioning
                            [ ] customer secret key saved  [ ] Tailscale on all computers
                            [ ] HTTPS certificates on  [ ] 3 tags added
Tool versions (admin):      output of: tofu version; tailscale version; kubectl version --client
```

**Never paste:** private keys (`*.pem`), the customer secret key, the Tailscale auth key, or the contents of
`~/.oci/config`. Your tenancy/user OCIDs aren't passwords, but this repo is public, so they stay in your local
git-ignored settings file too.

## How P2 will work between us
1. I write `infra/oci/` (network with no public ingress, 1 ARM VM, k3s + Tailscale via cloud-init, state in your
   bucket), plus `make infra-plan` / `make infra-apply` / `make kubeconfig`. CI checks the code (`tofu fmt`,
   `tofu validate`, `tofu test` with mocked providers) without any of your credentials.
2. You create the Tailscale auth key, put the three secrets in environment variables on the admin computer (I'll
   give you a template), and run `make infra-plan`, then `make infra-apply`.
3. You paste the **non-secret** results: the plan summary line, `kubectl get nodes -o wide`, and any error message
   (check it contains no keys first). I fix anything that fails, and we repeat until the P2 Definition of Done is met.
4. Trial extras (`infra/oci-trial/`, `make trial-*`) are separate and optional; they never touch the permanent node.
