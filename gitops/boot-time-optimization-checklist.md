# Boot Time Optimization Checklist

This checklist summarizes the boot-time optimization work completed so far for the Ubuntu 24.04 KPO node path.

## Image Build Optimizations

- [x] Built and used a custom Ubuntu 24.04 OKE worker image
- [x] Switched KPO to the optimized image OCID
- [x] Enabled image-time pre-pull for OKE hot-path images
- [x] Baked these images into the custom image:
  - `oke-public-vcn-native-ip-cni-plugin`
  - `oke-public-cloud-provider-oci`
  - `oke-public-kube-proxy`
  - `oke-public-proxymux-cli`
  - `public.ecr.aws/z2c7x8q5/bitnami/kubectl`
- [x] Enabled early `crio.service` startup during image build
- [x] Installed helper packages needed for bootstrap/debug timing:
  - `jq`
  - `curl`
  - `crictl`
- [x] Pre-created host CNI/bootstrap paths in the image:
  - `/opt/cni/bin`
  - `/etc/cni/net.d`
  - `/etc/oci-cni`
  - `/run/xtables.lock`
- [x] Added a bootstrap timing monitor to the image

## KPO Bootstrap Path Changes

- [x] Used the optimized image in [ocinodeclass.yaml](/home/bd/gh/private-oke-karpenter/gitops/c/kpo/ocinodeclass.yaml)
- [x] Used `metadata.user_data` for the Ubuntu bootstrap path
- [x] Added the Ubuntu compatibility shim in [pre-bootstrap-init.sh](/home/bd/gh/private-oke-karpenter/gitops/c/kpo/pre-bootstrap-init.sh)
- [x] Added a repeatable timing runbook in [karpenter-startup-timing-runbook.md](/home/bd/gh/private-oke-karpenter/gitops/karpenter-startup-timing-runbook.md)
- [x] Tested a synthetic startup-taint helper path
- [x] Removed that startup-taint helper after proving it added delay

## Measurements And Findings

- [x] Measured node bootstrap improvement versus the earlier baseline
- [x] Measured fresh `NodeClaim -> pod Running` timing
- [x] Captured guest-side timing markers from the node itself
- [x] Confirmed image/bootstrap is no longer the dominant delay
- [x] Confirmed the remaining floor is the native pod networking bring-up path

## Current Best Results

- earlier optimized node-bootstrap result:
  - about `98s` claim -> initialized
- later rerun after removing the synthetic startup-taint helper:
  - about `105s` claim -> initialized
- fresh end-to-end pod-start result:
  - about `110s` to `120s` claim -> pod running depending on the run
- August 21, 2026 rerun with explicit Ubuntu `imageId` plus OCI CNI asset preseed:
  - about `76s` claim -> initialized/ready
  - about `119s` demand -> workload container started
- August 21, 2026 rerun after fixing the startup-taint helper RBAC:
  - about `79s` pending-workload -> scheduled
  - about `81s` pending-workload -> container started
  - clean handoff, without fresh pod-sandbox IP-allocation failures
- August 21, 2026 rerun after disabling wait-online services:
  - `32s` claim -> launch
  - `66s` claim -> node joined/Ready
  - `106s` claim -> initialized/workload schedulable
  - `109s` claim -> workload container started
  - `112s` demand -> workload container started

## Current Bottleneck

- [x] `vcn-native-ip-cni` readiness is now the main remaining delay
- [x] host CNI config appears only near the node-ready window
- [x] kubelet/pod sandbox failures during this window included `unable to allocate IP address`
- [x] preseeded OCI CNI binaries improved node readiness materially, but did not remove the first-pod IP allocation delay

## Not Yet Solved

- [ ] reduce the remaining `Registered -> Initialized` `vcn-native-ip-cni` stabilization time on fresh nodes
- [ ] prove whether any of that remaining stabilization is configurable from this repo or is an OCI/OKE floor

## Repo Ownership Boundary

- [x] kept `secondaryVnicConfigs[*].ipCount` as Git-managed manifest intent in `gitops/c/kpo/ocinodeclass.yaml.tftpl`
- [x] kept KPO node shape as Git-managed manifest intent in `gitops/c/kpo/ocinodeclass.yaml.tftpl`
- [x] did not expand Terraform inputs for OKE-managed `kube-system` CNI behavior
- [x] documented the split between:
  - provider floor
  - guest bootstrap
  - post-bootstrap CNI gate
- [x] verified that `NodeClaim -> Launched` is mostly OCI/provider floor, not Ubuntu guest boot time
