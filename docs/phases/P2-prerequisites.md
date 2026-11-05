# Before P2: what to do, and what to bring

P2 builds the always-on cluster: **k3s on 2 Oracle Cloud Always Free ARM VMs**, with no public ports, reachable from your
computers over **Tailscale**. I write all the OpenTofu code; **you** run it from your computer, so your cloud keys
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
| [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.8 | ✅ | — | `tofu version` |
| [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (optional, helps with debugging) | optional | — | `oci --version` |

## 2. Oracle Cloud (OCI) account
1. Sign up at **cloud.oracle.com** → "Start for free".
   - **Home region: choose carefully, it can never be changed.** Always Free ARM machines exist only in your home
     region. Pick one near you. Popular regions sometimes run out of free ARM capacity; P2 handles that with
     retries, so don't worry too much.
   - A card is requested **for identity verification only**. Always Free resources are never charged.
2. **Budget alarm** (safety net): *Billing & Cost Management → Budgets → Create budget*. Use the root
   compartment, amount **$1**, and an alert rule at **1% of actual spend** to your email. You'll hear about any
   cent spent.
3. **API key** (lets OpenTofu manage resources):
   - *Profile icon (top right) → My profile → API keys → Add API key → Generate API key pair*.
   - **Download the private key**, then press *Add*.
   - Copy the "Configuration file preview" into `~/.oci/config` on the admin computer, and set `key_file=` to where
     you saved the private key (e.g. `~/.oci/qops_api_key.pem`).
   - `chmod 600 ~/.oci/config ~/.oci/qops_api_key.pem`.
   - Test (if you installed the OCI CLI): `oci iam region list` returns a list.
4. **Bucket for OpenTofu state**, so any computer sees the same infrastructure state:
   - *Storage → Buckets → Create bucket*, name **`qops-tofu-state`**, Standard tier, **enable Object Versioning**.
   - Note the **Object Storage namespace** shown on the bucket page (a short random-looking string).
5. **S3-compatible key for that bucket**: *Profile → My profile → Customer secret keys → Generate secret key*.
   Name it `qops-tofu`, then **copy the secret immediately** (it's shown once) and the Access Key.
   Store both in your password manager. In P2 they go into environment variables on the admin computer only.

## 3. Tailscale
1. Sign up at **login.tailscale.com** (GitHub or Google login is fine). The free Personal plan is enough.
2. Install Tailscale on **every computer you work from** and run `tailscale up`. They should all appear under *Machines*.
3. *DNS* page: keep **MagicDNS** on, and enable **HTTPS Certificates** (P3 uses them for the web UIs).
   Note the **Tailnet DNS name** at the top, like `tail1234ab.ts.net`.
4. *Access controls*: add these tags to the policy file (inside the top-level `{ … }`), then save:
   ```jsonc
   "tagOwners": {
     "tag:qops-node":    ["autogroup:admin"],   // the two cluster VMs (P2)
     "tag:k8s-operator": [],                    // Tailscale Kubernetes operator (P3)
     "tag:k8s":          ["tag:k8s-operator"],  // services the operator exposes (P3)
   },
   ```
   If your policy already has a `tagOwners` block, add the three lines to it.
5. **Don't create the auth key yet.** Create it right before running P2 (it should expire soon after). Settings for later:
   *Settings → Keys → Generate auth key*: Reusable ✅ · Ephemeral ❌ · Pre-approved ✅ · Tags `tag:qops-node` · Expiry 1 day.

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
Object Storage namespace:   e.g. axq1bcdefg2h
State bucket name:          qops-tofu-state (or yours)
Tailnet DNS name:           e.g. tail1234ab.ts.net
Admin computer OS:          e.g. Ubuntu 24.04 / macOS 15 / Windows 11 + WSL2
Other computers' OS:        …
Checklist:                  [ ] budget alarm  [ ] ~/.oci/config works  [ ] bucket + versioning
                            [ ] customer secret key saved  [ ] Tailscale on all computers
                            [ ] HTTPS certificates on  [ ] 3 tags added
Tool versions (admin):      output of: tofu version; tailscale version; kubectl version --client
```

**Never paste:** private keys (`*.pem`), the customer secret key, the Tailscale auth key, or the contents of
`~/.oci/config`. Your tenancy/user OCIDs aren't passwords, but this repo is public, so they stay in your local
git-ignored settings file too.

## How P2 will work between us
1. I write `infra/oci/` (network with no public ingress, 2 ARM VMs, k3s + Tailscale via cloud-init, state in your
   bucket), plus `make infra-plan` / `make infra-apply` / `make kubeconfig`. CI checks the code (`tofu fmt`,
   `tofu validate`, `tofu test` with mocked providers) without any of your credentials.
2. You create the Tailscale auth key, put the three secrets in environment variables on the admin computer (I'll
   give you a template), and run `make infra-plan`, then `make infra-apply`.
3. You paste the **non-secret** results: the plan summary line, `kubectl get nodes -o wide`, and any error message
   (check it contains no keys first). I fix anything that fails, and we repeat until the P2 Definition of Done is met.
