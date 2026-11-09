# ADR 0011 — Tailnet policy and node auth key are managed by OpenTofu

- **Status:** Accepted
- **Date:** 2026-11-09
- **Relates to:** [ADR 0002](0002-oci-always-free-and-tailscale.md), [ADR 0008](0008-single-node-a1-cluster.md)

## Context
The node must join the tailnet at first boot. That needs an auth key. Making keys by hand means a secret copied
through the clipboard, and a key that's either long-lived (risky) or expired by the time it's used. The tailnet policy
(tags, who can reach what, Tailscale SSH) was also edited by hand in the admin console, outside Git.

## Decision
`infra/oci/` uses the Tailscale provider with an API access token kept in `~/.config/qops/tailscale.env`:
- **`tailscale_acl`** holds the whole tailnet policy in Git. It defines the tags; personal devices reach everything;
  tagged infrastructure reaches only other tagged infrastructure; members get Tailscale SSH to nodes as `ubuntu`.
  It overwrites the policy in the admin console.
- **`tailscale_tailnet_key`** creates a **single-use, pre-approved, `tag:qops-node` key that expires after 1 hour**
  during `apply`. It goes to the node in cloud-init user data and is deleted from disk after use.
  `recreate_if_invalid = "never"` keeps plans free of drift; `make infra-rebuild` replaces key and node together.
- **State and plans are encrypted** (OpenTofu `encryption`, PBKDF2 + AES-GCM) because they contain that key. The
  passphrase is in `~/.config/qops/tofu.env` and the user's password manager.
- Access to the node is **Tailscale SSH**. The SSH key pair is break-glass only, for Oracle's console connection.

## Consequences
- Nobody makes or pastes an auth key. A leaked old key is useless after an hour or one use.
- The key is visible in the instance's user data to anyone with OCI console access to the compartment (only the
  user); it's spent by then.
- Policy edits in the Tailscale console are overwritten on the next apply. Change `infra/oci/tailscale.tf` instead.
- The API access token expires after 90 days. Renew it with `make tailscale-login` (delete the old env file first).
  P3 adds an OAuth client for the Kubernetes operator.
