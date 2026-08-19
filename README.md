# private_oke_karpenter

Private OKE baseline with GitOps-managed Karpenter Provider for OCI (KPO).

## Model

- Terraform owns OCI and OKE infrastructure.
- Git owns KPO runtime state.
- Argo CD applies Git state to the cluster.

Terraform does not apply KPO manifests directly.

## Deploy

Brand-new cluster:

1. Run `terraform apply`.
2. Commit and push rendered GitOps files:
   - `gitops/c/kpo/values.yaml`
   - `gitops/c/kpo/ocinodeclass.yaml`
3. Seed Argo once:

```bash
make gitops-bootstrap
```

4. Wait for Argo sync.

Steady state:

1. Run `terraform apply`.
2. Commit and push rendered GitOps files.
3. Wait for Argo sync.

## Important

- The committed GitOps files are environment-specific.
- If infra values change, re-render and push:
  - `gitops/c/kpo/values.yaml`
  - `gitops/c/kpo/ocinodeclass.yaml`
- `settings.apiserverEndpoint` must be host-only, not `host:port`.

## Ubuntu KPO Note

KPO uses `OCINodeClass.spec.preBootstrapInitScript`, not full `metadata.user_data`.

For Ubuntu custom images, the readable source is:

- `gitops/c/kpo/pre-bootstrap-init.sh`

It provides the compatibility shim KPO needs for Ubuntu worker bootstrap.

Validated on August 19, 2026:

- KPO can select a custom Ubuntu image through `imageType: OKEImage` plus `imageFilter`.
- The custom image must resolve to a cluster-compatible Kubernetes version.
- In this repo, `osFilter: Canonical Ubuntu` and `osVersionFilter: "24.04"` worked with a custom image after its `k8s_version` tag was changed to match the cluster version and KPO was restarted.
- End-to-end proof was a Karpenter node joining as `Ubuntu 24.04.4 LTS` and running the `inflate` workload.

Important:

- Tagging alone does not change the actual kubelet version inside the image.
- A mismatched real kubelet/image version can still be unsafe even if KPO accepts the image after tag changes.

## Destroy

Do not start with raw `terraform destroy`.

1. Remove demand workloads from Git.
2. Remove or disable `NodePool` and `OCINodeClass` in Git.
3. Wait for Argo sync.
4. Verify Karpenter nodes are gone.
5. Run `terraform destroy`.

## Key Paths

- `gitops/c/chart.yaml`: Argo app for KPO chart
- `gitops/c/manifests.yaml`: Argo app for `OCINodeClass` and `NodePool`
- `gitops/c/kpo/values.yaml`: committed KPO values
- `gitops/c/kpo/ocinodeclass.yaml`: committed node class
- `gitops/c/kpo/nodepool.yaml`: committed node pool
