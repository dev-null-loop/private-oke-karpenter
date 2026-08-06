# GitOps

The `gitops/` tree in this repo now acts mainly as a generated/rendered
workspace for KPO values and manifests.

- The default install path is automated bastion bootstrap with Helm and
  `kubectl`.
- Argo CD can still consume these files if you want, but it is no longer
  required for the basic standalone test flow.

The OKE bootstrap `user_data` patch is committed directly in
`ocinodeclass.yaml` so Karpenter-launched workers keep the fixed bootstrap path.
The human-readable source for that payload lives in
`gitops/clusters/private-oke-karpenter/karpenter/oke-bootstrap-user-data.sh`.
