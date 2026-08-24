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
   - `gitops/c/kpo/nodepool.yaml`
3. Seed Argo once:

```bash
make gitops-bootstrap
```

4. Wait for Argo sync.

Steady state:

1. Run `terraform apply`.
2. Commit and push rendered GitOps files.
3. Wait for Argo sync.

Optional:

- set `karpenter.controller_image` to pin Argo/Helm to a custom KPO controller image

## Important

- The committed GitOps files are environment-specific.
- If infra values change, re-render and push:
  - `gitops/c/kpo/values.yaml`
  - `gitops/c/kpo/ocinodeclass.yaml`
  - `gitops/c/kpo/nodepool.yaml`
- `settings.apiserverEndpoint` must be host-only, not `host:port`.

## Ubuntu KPO Note

This repo now supports three bootstrap modes:

- `bootstrap_mode = "native"`
- `bootstrap_mode = "prebootstrap"`
- `bootstrap_mode = "metadata"`

Current default:

- `image_type = "OKEImage"`
- `bootstrap_mode = "native"`
- `bootstrap_mode = "metadata"`
- `image_source = "filter"`
- `shape.ocpus = 8`
- `shape.memory_in_gbs = 32`
- `pod_ip_count = 8`
- `capacityType = "on-demand"`
- `instanceShape = "VM.Standard.E3.Flex"`

Recommended usage:

- use `image_source = "filter"` when you want OKE to resolve an image through the image filter path
- use `image_source = "image_id"` when you want to pin a specific image from `karpenter.node_image`
- use `OKEImage + native` for official OKE images that already satisfy the default KPO/OKE bootstrap contract
- use `Custom + metadata` with a patched KPO controller image when you want customer-owned bootstrap through `metadata.user_data`
- use `OKEImage + prebootstrap` only when you want the smaller compatibility shim around the default KPO bootstrap flow
- use `capacityType` and `instanceShape` when you want to switch NodePool scheduling scenarios quickly

For Ubuntu custom images, the readable source is:

- `gitops/c/kpo/pre-bootstrap-init.sh`
- `gitops/c/kpo/metadata-user-data-ubuntu.yaml.tftpl`

The first provides the compatibility shim KPO needs for Ubuntu worker bootstrap when KPO still calls `/etc/oke/oke-install.sh`.

The second provides a full cloud-init payload that fetches KPO-injected metadata keys from IMDS and calls `/usr/bin/oke bootstrap` directly.

Validated on August 19, 2026:

- KPO can select a custom Ubuntu image through `imageType: OKEImage` plus `imageFilter`.
- This repo can render `imageType: Custom` plus `metadata.user_data` when `bootstrap_mode = "metadata"`.
- Stock KPO controller images still need a controller-image override for that path because the published controller rejects `imageType: Custom` during metadata construction.
- The custom image must resolve to a cluster-compatible Kubernetes version.
- In this repo, `osFilter: Canonical Ubuntu` and `osVersionFilter: "24.04"` worked with a custom image after its `k8s_version` tag was changed to match the cluster version and KPO was restarted.
- End-to-end proof for `Custom + metadata` requires the patched controller image to be deployed.

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

## Timing

Single-node Karpenter timing benchmark:

1. `make demand-delete`
2. `date -u --iso-8601=seconds`
3. `make demand-single-node`
4. watch:
   - `kubectl get nodeclaims -w`
   - `kubectl get nodes -w`
   - `kubectl get pods -n default -o wide -w`

Detailed procedure and a measured August 20, 2026 reference run are in:

- `gitops/karpenter-startup-timing-runbook.md`

Lab model and scenario-control boundary:

- `gitops/LAB_MODEL.md`

## Key Paths

- `gitops/c/chart.yaml`: Argo app for KPO chart
- `gitops/c/manifests.yaml`: Argo app for `OCINodeClass` and `NodePool`
- `gitops/c/kpo/values.yaml`: committed KPO values
- `gitops/c/kpo/ocinodeclass.yaml`: committed node class
- `gitops/c/kpo/nodepool.yaml`: committed node pool
- `gitops/custom-kpo-image.md`: custom controller image flow
