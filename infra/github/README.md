# infra/github — repository settings (P3)

Branch protection for `main` as a GitHub ruleset:
- **No direct pushes:** changes come through pull requests.
- **No merge until CI passes:** every main CI job must be green first.
- **No force pushes** and **no deletion** of `main`.
- **One exception:** deploy keys may push. The only deploy key is the one this stack creates for `images.yml`,
  which commits image tag bumps to `deploy/envs/oci/values.yaml`. Its private key is the `IMAGE_BUMP_DEPLOY_KEY`
  Actions secret and lives in the encrypted state. A personal account can't exempt the GitHub Actions app itself.

Run it from the admin computer:
```bash
make github-plan
make github-apply
```
The token comes from `gh auth token` (your GitHub CLI login). In WSL, the Windows `gh.exe` works. State is
stored next to `infra/oci`'s in the `qops-tofu-state` bucket, encrypted with the same passphrase.

If you rename a CI job, update `required_checks` in `main.tf` in the same PR. Otherwise PRs wait forever for a
check that no longer exists.
