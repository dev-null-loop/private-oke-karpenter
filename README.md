# private_oke_karpenter

Private OKE baseline plus OCI Karpenter (KPO) install and validation harness.

This repo is derived from `private_oke_oidc`, but scoped for:
- private OKE cluster creation
- bootstrap node pool creation
- bastion VM access path
- automated bastion-side KPO bootstrap with Helm and `kubectl`
- generated KPO values plus generated `OCINodeClass` and `NodePool` manifests
- Fortinet-style public-worker validation with OCI VCN-native pod networking
- optional synthetic test workload generation

## Flow

1. `terraform apply` builds the private OKE cluster, bootstrap node pool, bastion VM, and kubeconfig.
2. Terraform renders KPO values, `OCINodeClass`, `NodePool`, and optional test workload content.
3. Bastion cloud-init installs `kubectl`, OCI CLI, and Helm.
4. Bastion cloud-init installs the KPO Helm chart and applies the rendered manifests automatically.


## Prerequisites

Before installing OCI Karpenter in this stack, make sure the following are true:

- OKE cluster version is `>= v1.31`.
- The cluster already has bootstrap worker capacity so the KPO controller can run before Karpenter provisions new nodes.
- If the cluster uses OCI VCN-native pod networking, set `ociVcnIpNative: true` in the KPO values and use a compatible OciIpNativeCNI add-on version.
- The bastion host or another machine with private network reachability can access the private OKE API endpoint.
- Helm is available on the bastion for operator use.
- KPO IAM policies are created before Argo sync installs the KPO chart.
- For this public repository, Argo CD should use the HTTPS repo URL.
- For private repositories, Argo CD must already have repository credentials before sync can succeed.

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
- For the Fortinet investigation path, use a public `nodes` subnet for the worker primary VNIC and keep KPO pod IP allocation on a dedicated private `kpo_pods` subnet.
- `primary_vnic_config.assign_public_ip = true` controls whether Karpenter-launched workers request a public IP on the primary VNIC.
- `secondary_vnic_config` controls only the additional VNICs that back OCI VCN-native pod IP allocation. It does not by itself prove that normal pod egress will SNAT behind the worker public IP.
- The optional synthetic workload under `karpenter.test_workload` is just a convenient pending-workload trigger. It is not specific to Fortinet unless you explicitly enable it for that purpose.
- For long-term KPO operation with secondary VNICs, separate node and pod subnets are usually safer than reusing the same subnet, because IP fragmentation can cause NativePodNetwork failures even when total free IP count looks high.

## Bootstrap Model

This repo uses a self-contained automated bootstrap split:

- Terraform owns OCI, OKE, IAM, and rendered KPO content
- the bastion instance prepares access tooling and installs KPO automatically
- Argo CD is not required for the basic KPO test path

## Cloud-Init Limitation

OCI instance `metadata.user_data` should be treated as day-0 bootstrap input.
In this stack, changing bastion cloud-init content can force bastion replacement.

Tradeoff:

- this is simpler than Argo CD for a standalone test stack
- changing bastion bootstrap cloud-init can still force bastion replacement

Practical split:

- day-0 via bastion cloud-init:
  - `kubectl`
  - OCI CLI
  - Helm
  - bastion kubeconfig placement
  - KPO Helm install
  - `OCINodeClass` apply
  - `NodePool` apply
  - optional test workload apply

## OKE Bootstrap Patch

Karpenter-launched OKE workers in this repo embed a committed custom
`OCINodeClass.spec.metadata.user_data` payload in `gitops/.../ocinodeclass.yaml`.
The readable source script is
`gitops/clusters/private-oke-karpenter/karpenter/oke-bootstrap-user-data.sh`.

Why:

- OKE bootstrap expects host-only `apiserver_host` metadata and then appends its
  own worker bootstrap port
- the custom `user_data` path preserves Oracle bootstrap while exporting the
  metadata values in the form OKE expects
- without this patch, Karpenter nodes can launch successfully in OCI but fail
  before stable cluster registration

## Debugging Notes

Proven failure modes seen in this repo on August 6, 2026:

- If the shim renders `"$$(fetch_md ...)"` instead of `"$(fetch_md ...)"`,
  `cloud-final` fails before OKE bootstrap with broken values such as
  `3606(fetch_md apiserver_host)` and `base64: invalid input`.
- `APISERVER_ENDPOINT` must be host-only. If the shim passes `10.0.0.8:6443`,
  OKE bootstrap constructs `https://10.0.0.8:6443:12250/workerNodeBootstrap`
  and retries forever with `lookup 10.0.0.8:6443: no such host`.
- The bastion bootstrap is one-shot cloud-init. `terraform apply` updates the
  rendered KPO manifests on disk, but it does not automatically re-run
  `kubectl apply` on an already-created bastion.
- Because of that limitation, after changing `gitops/.../ocinodeclass.yaml`
  or other rendered KPO manifests, apply them manually to the cluster and
  recycle the affected `NodeClaim`s.
- After both fixes were applied and fresh `NodeClaim`s were launched, the new
  Karpenter nodes `10.0.10.61` and `10.0.10.206` registered successfully and
  reached `Ready` on August 6, 2026.
- The Karpenter workers that registered successfully were running kernel
  `5.15.0-322.203.3.4.el8uek.x86_64`.
- A few `NodeAffinity` failed test-workload pods can remain from earlier bad
  bootstrap cycles. Those are stale failed replicas, not proof that the live
  replacement nodes are still broken.

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

- `karpenter.tf`: KPO render wiring and user-facing outputs
- `karpenter.variables.tf`: operator and test-workload settings
- `karpenter.auto.tfvars`: KPO settings
- `addons/karpenter/*`: KPO content generation logic and debug script
- `gitops/*`: generated KPO values/manifests written into the repo workspace
- `gitops/clusters/private-oke-karpenter/karpenter/oke-bootstrap-user-data.sh`: readable source for the committed `user_data` payload
- `userdata/helm.yaml.tftpl`: bastion cloud-init that prepares kubeconfig and tools
- `userdata/kpo-bootstrap.yaml.tftpl`: bastion cloud-init that installs KPO and applies rendered manifests

## Important notes

- Keep one bootstrap node pool in Terraform. KPO should not bootstrap itself from zero.
- If you use OCI VCN-native pod networking, set `ociVcnIpNative=true` in the KPO values.
- For separate OCI VCN-native pod subnets, explicit secondary-VNIC configuration and pod-subnet control are the important knobs.
- Argo CD is optional. The default path is bastion bootstrap with Helm and `kubectl`.
