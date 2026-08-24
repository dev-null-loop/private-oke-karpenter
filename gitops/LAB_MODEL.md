# Lab Model

This repo is a fast KPO scenario lab, not a strict production GitOps repo.

## Goal

Answer customer and internal KPO questions quickly by switching explicit
scenario knobs without hand-editing low-level OCI wiring in multiple places.

## Control Surface

The active scenario surface is the local `karpenter.auto.tfvars` `karpenter`
object.

Current first-class scenario knobs include:

- `image_type`
- `image_source`
- `bootstrap_mode`
- `node_image`
- `image_filter`
- `controller_image`
- `shape.ocpus`
- `shape.memory_in_gbs`
- `pod_ip_count`
- `capacityType`
- `instanceShape`
- `limits.cpu`
- `limits.memory`

These knobs should map to customer or lab scenarios directly, not to renderer
implementation details.

## Generated Files

For this lab setup, these KPO files are intentionally generated:

- `gitops/c/kpo/values.yaml`
- `gitops/c/kpo/ocinodeclass.yaml`
- `gitops/c/kpo/nodepool.yaml`

They are generated because the lab frequently changes:

- subnet wiring
- image IDs and filter paths
- bootstrap payloads
- scenario-specific KPO settings

## Design Rule

- scenario intent belongs in explicit knobs
- infrastructure facts may be resolved in Terraform
- templates should stay readable and close to final YAML
- render files should stay thin
- avoid defensive `useX` flags and implementation-shaped toggles
