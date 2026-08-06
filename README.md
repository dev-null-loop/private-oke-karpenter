# private_oke_karpenter

Private OKE baseline plus OCI Karpenter (KPO) install and validation harness.

This repo is derived from `private_oke_oidc`, but scoped for:
- private OKE cluster creation
- bootstrap node pool creation
- bastion VM access path
- Argo CD bootstrap from the bastion
- generated GitOps-managed KPO values plus generated `OCINodeClass` and `NodePool` manifests
- Fortinet-style public-worker validation with OCI VCN-native pod networking
- optional synthetic test workload generation

## Flow

1. `terraform apply` builds the private OKE cluster, bootstrap node pool, bastion VM, and kubeconfig.
2. Terraform renders GitOps-managed KPO values, Argo applications, `OCINodeClass`, and `NodePool` content under `gitops/`.
3. Bastion cloud-init installs `kubectl`, OCI CLI, Helm, and Argo CD.
4. Bastion cloud-init applies the Argo root application.
5. Argo CD reconciles the KPO Helm release and the generated Karpenter manifests from this repo.


## Prerequisites

Before installing OCI Karpenter in this stack, make sure the following are true:

- OKE cluster version is `>= v1.31`.
- The cluster already has bootstrap worker capacity so the KPO controller can run before Karpenter provisions new nodes.
- If the cluster uses OCI VCN-native pod networking, set `ociVcnIpNative: true` in the KPO values and use a compatible OciIpNativeCNI add-on version.
- The bastion host or another machine with private network reachability can access the private OKE API endpoint.
- Helm is available on the bastion (the provided bastion bootstrap path installs it).
- KPO IAM policies are created before Argo sync installs the KPO chart.
- For this public repository, Argo CD should use the HTTPS repo URL.
- For private repositories, Argo CD must have repository credentials before sync can succeed.

## Required IAM Policies

KPO runs in-cluster and uses OCI workload identity. The KPO controller service account must be allowed to manage OCI resources needed for node provisioning.

Typical policy shape:

```text
Allow any-user to <verb> <resource> in <location> where all {
  request.principal.type = 'workload',
  request.principal.namespace = '<karpenter-namespace>',
  request.principal.service_account = '<karpenter-service-account>',
  request.principal.cluster_id = '<oke-cluster-ocid>'
}
```

For this stack, the default namespace/service account are typically:
- namespace: `karpenter`
- service account: `karpenter`

Minimum controller policies:

```text
Allow any-user to manage instance-family in compartment <compartment-name> where all { ... }
Allow any-user to manage volumes in compartment <compartment-name> where all { ... }
Allow any-user to manage volume-attachments in compartment <compartment-name> where all { ... }
Allow any-user to manage virtual-network-family in compartment <compartment-name> where all { ... }
Allow any-user to inspect compartments in compartment <compartment-name> where all { ... }
```

Optional policies if you enable the related features in `OCINodeClass`:

```text
Allow any-user to use compute-capacity-reservations in compartment <compartment-name> where all { ... }
Allow any-user to use compute-clusters in compartment <compartment-name> where all { ... }
Allow any-user to use cluster-placement-groups in compartment <compartment-name> where all { ... }
Allow any-user to use tag-namespaces in compartment <compartment-name> where all { ... }
```

## Node Registration Policy

Instances launched by KPO also need permission to join the OKE cluster.
Create a dynamic group that matches the compartment(s) where KPO will launch worker nodes, then allow `CLUSTER_JOIN`.

Example dynamic group rule:

```text
ALL {instance.compartment.id = '<node-compartment-ocid>'}
```

Example policy:

```text
Allow dynamic-group <domain-name>/<dynamic-group-name> to {CLUSTER_JOIN} in compartment <compartment-name>
```

## Networking Notes

- This repo is designed for private OKE clusters.
- Argo CD bootstrap is performed from the bastion or another host that can reach the private API endpoint.
- For the Fortinet investigation path, use a public `nodes` subnet for the worker primary VNIC and keep KPO pod IP allocation on a dedicated private `kpo_pods` subnet.
- `primary_vnic_config.assign_public_ip = true` controls whether Karpenter-launched workers request a public IP on the primary VNIC.
- `secondary_vnic_config` controls only the additional VNICs that back OCI VCN-native pod IP allocation. It does not by itself prove that normal pod egress will SNAT behind the worker public IP.
- The optional synthetic workload under `karpenter.test_workload` is just a convenient pending-workload trigger. It is not specific to Fortinet unless you explicitly enable it for that purpose.
- For long-term KPO operation with secondary VNICs, separate node and pod subnets are usually safer than reusing the same subnet, because IP fragmentation can cause NativePodNetwork failures even when total free IP count looks high.

## Bastion Bootstrap Model

This repo now prefers a minimalist GitOps day-0 flow:

- Terraform owns OCI and OKE prerequisites
- the bastion instance bootstraps Argo CD
- Argo CD owns the KPO Helm release and Karpenter manifests

Why:

- a single reconciliation model after bootstrap
- cleaner separation between bootstrap and ongoing cluster state
- a clearer ownership boundary:
- Terraform: cloud resources and IAM
- bastion bootstrap: Argo CD install and root application
- Argo CD: KPO chart and manifests

## Cloud-Init Limitation

OCI instance `metadata.user_data` should be treated as day-0 bootstrap input.
In this stack, changing bastion cloud-init content can force bastion replacement.

That matters because GitOps bootstrap content changes more often than the bastion
itself. If Argo CD install logic, root application content, or related bootstrap
fragments are embedded directly in bastion `user_data`, ordinary GitOps changes
can turn into instance recreation pressure.

Recommended workaround:

- keep bastion `user_data` minimal and stable
- use cloud-init only for base tools and initial kubeconfig placement
- move mutable Argo/Karpenter bootstrap steps out of `user_data`
- perform day-1 changes through a post-provision bastion step, OCI instance
  agent command execution, or a manual/operator bootstrap command

Practical split:

- day-0 via cloud-init:
  - `kubectl`
  - OCI CLI
  - Helm
  - bastion kubeconfig placement
- day-1 outside cloud-init:
  - Argo CD install/update
  - repository secret apply
  - root application apply/update
  - Karpenter sync/reconciliation changes

## Fortinet Validation Mode

The example files are biased toward the Fortinet/KPO validation path:

- bootstrap node pool stays in Terraform
- Karpenter workers use the public `nodes` subnet as their primary subnet
- KPO pod IP allocation uses a separate private `kpo_pods` subnet
- the synthetic test workload is disabled by default

This keeps the repo aligned with the actual question being investigated:

- can Karpenter-launched public workers plus OCI VCN-native pod networking produce the Fortinet-requested egress behavior

The answer still depends on live runtime validation, but these defaults keep the repo aligned with the Fortinet path instead of an older bug-reproduction path.

## Files

- `karpenter.tf`: thin root module call and user-facing outputs
- `karpenter.variables.tf`: operator and test-workload settings
- `karpenter.auto.tfvars.example`: example Karpenter settings
- `addons/karpenter/*`: KPO GitOps artifact generation logic and debug script
- `gitops/*`: Argo-managed KPO chart/manifests tree
- `userdata/helm.yaml.tftpl`: bastion cloud-init that prepares kubeconfig and tools
- `userdata/argocd-bootstrap.yaml.tftpl`: bastion cloud-init that installs Argo CD and applies the root application

## Important notes

- Keep one bootstrap node pool in Terraform. KPO should not bootstrap itself from zero.
- If you use OCI VCN-native pod networking, set `ociVcnIpNative=true` in the KPO values.
- For separate OCI VCN-native pod subnets, explicit secondary-VNIC configuration and pod-subnet control are the important knobs.
- The bastion instance path now bootstraps Argo CD rather than applying KPO resources directly.
