# GitOps

`gitops/` is the runtime source of truth for KPO in this repo.

Terraform does not render or apply KPO manifests anymore.

## What Lives Here

- Argo CD application manifests
- committed KPO Helm values
- committed `OCINodeClass`
- committed `NodePool`
- readable bootstrap hook source

## Bootstrap

The bastion installs Argo CD. After you patch environment-specific values, apply:

- `gitops/c`

After that, Argo CD owns reconciliation of the KPO chart and manifests from Git.

## Important Constraint

These manifests are committed and environment-specific.

If infra changes and you get new:

- subnet OCIDs
- compartment OCIDs
- API endpoint values

you must update the GitOps files accordingly.
