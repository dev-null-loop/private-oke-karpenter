# private_oke_karpenter

Private OKE baseline plus pure-GitOps OCI Karpenter (KPO) validation stack.

## Ownership Model

- Terraform owns OCI and OKE infrastructure:
  - VCN, subnets, gateways, security lists
  - OKE cluster
  - bootstrap managed node pool
  - bastion
  - IAM for KPO and bastion kubeconfig access
- GitOps owns KPO runtime state:
  - Argo CD applications
  - KPO chart values
  - `OCINodeClass`
  - `NodePool`
  - optional demand workloads if you add them

Terraform no longer renders or applies KPO manifests.

## Actual Deploy Model

This repo is not a one-step blank-environment deployment.

Because you do not know the real environment values in advance, deployment is now a 2-step process:

1. `terraform apply`
2. update committed GitOps environment files, then apply/sync GitOps

The environment-specific files are:

- `gitops/c/kpo/values.yaml`
- `gitops/c/kpo/ocinodeclass.yaml`

## Exact Deploy Steps

1. Run `terraform apply`
- this creates:
  - OKE cluster
  - bootstrap managed node pool
  - bastion
  - IAM for KPO
- bastion cloud-init installs:
  - `kubectl`
  - OCI CLI
  - Helm
  - Git
  - Argo CD

2. Discover the real environment values from the created stack
- at minimum:
  - API server private endpoint host
  - subnet OCIDs for:
    - primary node subnet
    - pod secondary subnet
  - any changed compartment OCIDs if applicable

3. Update the committed GitOps files
- patch:
  - `gitops/c/kpo/values.yaml`
  - `gitops/c/kpo/ocinodeclass.yaml`

Important:
- `settings.apiserverEndpoint` must be host-only, not `host:port`
- for example: `10.0.0.8`, not `10.0.0.8:6443`

4. Apply the root GitOps app manifests
- for example from bastion:

```bash
kubectl apply -k /home/opc/private-oke-karpenter/gitops/c
```

5. Let Argo CD reconcile
- `chart.yaml`
- `manifests.yaml`

After that:
- Argo deploys the KPO Helm chart
- Argo applies the committed `OCINodeClass`
- Argo applies the committed `NodePool`

## GitOps Layout

- `gitops/c/chart.yaml`
  - Argo application for the KPO Helm chart
- `gitops/c/manifests.yaml`
  - Argo application for committed `OCINodeClass` and `NodePool`
- `gitops/c/kpo/values.yaml`
  - committed Helm values
- `gitops/c/kpo/ocinodeclass.yaml`
  - committed KPO node class
- `gitops/c/kpo/nodepool.yaml`
  - committed Karpenter node pool
- `gitops/c/kpo/pre-bootstrap-init.sh`
  - readable source for the committed `preBootstrapInitScript`

## Bastion Bootstrap

- `userdata/helm.yaml.tftpl`
  - installs `kubectl`, OCI CLI, Helm, Git, and kubeconfig
- `userdata/argocd-bootstrap.yaml.tftpl`
  - installs Argo CD
  - clones this repo on the bastion
  - does not auto-apply the Karpenter GitOps apps

This is still day-0 cloud-init on the bastion. Changing bastion cloud-init can still force bastion replacement.

## KPO Bootstrap Hook

Karpenter-launched workers use:

- `OCINodeClass.spec.preBootstrapInitScript`

not full `metadata.user_data`.

The readable source lives in:

- `gitops/c/kpo/pre-bootstrap-init.sh`

The committed `OCINodeClass` contains the base64 payload because that is how KPO expects the field.

## Important Constraint

This repo is pure GitOps for KPO runtime state, but the committed GitOps manifests are environment-specific.

That means if you recreate infra with different:

- subnet OCIDs
- compartment OCIDs
- API endpoint
- image assumptions

you must update the committed GitOps files to match the new environment.

## Destroy Flow

Do not run raw `terraform destroy` first.

Use this order:

1. Remove demand workloads from Git, if any.
2. Remove or disable `NodePool` / `OCINodeClass` in Git.
3. Let Argo CD sync the removal.
4. Wait until:
   - `kubectl get nodeclaims -A` is empty
   - Karpenter-created OCI instances are gone
5. Run `terraform destroy`

Reason:

- Terraform does not own Karpenter-created OCI instances.
- KPO must be allowed to drain and delete its own `NodeClaims` first.

## Current Validation Notes

On Thursday, August 6, 2026, this repo was used as a healthy control case for:

- `BM.Standard3.64`
- OCI VCN-native pod networking
- primary worker VNIC on `nodes`
- secondary pod VNIC on `kpo_pods`

The stack successfully:

- launched BM nodes through KPO
- recycled them through Karpenter
- re-registered replacement BM nodes
- completed `ListVnicAttachments` and `GetVnic` checks

That proved shape alone did not reproduce the Fortinet incident in this stack.

## Files

- `core.auto.tfvars`
  - bastion cloud-init references
- `karpenter.auto.tfvars`
  - KPO infra-prereq and IAM toggles only
- `karpenter.variables.tf`
  - Terraform-side KPO prereq schema
- `identity.tf`
  - KPO and bastion IAM
- `gitops/*`
  - single source of truth for KPO runtime state
