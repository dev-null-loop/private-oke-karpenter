# GitOps

This repo uses Argo CD as the default KPO deployment path.

- Bastion cloud-init bootstraps Argo CD only.
- Argo CD then reconciles:
  - the KPO Helm release
  - `OCINodeClass`
  - `NodePool`
  - optional test workload

For this public repository, Argo CD should use:

- `https://github.com/dev-null-loop/private-oke-karpenter.git`

For private repositories, Argo CD still needs repository credentials.
Provide them either by:

- setting `karpenter.gitops.repository_secret` so bastion bootstrap applies the
  secret automatically
- or applying an equivalent Argo CD repository secret separately
