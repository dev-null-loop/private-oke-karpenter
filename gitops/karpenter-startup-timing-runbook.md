# Karpenter Startup Timing Runbook

Purpose:

- measure how long KPO-managed nodes take to appear and become usable
- separate Karpenter/OCI provisioning time from in-node bootstrap time
- provide a repeatable before/after method for image or bootstrap optimizations

This runbook is written for the current model in this repo:

- Terraform manages OCI and OKE infrastructure
- GitOps manages KPO runtime state
- KPO currently uses `preBootstrapInitScript`, not full `metadata.user_data`

See:

- [README.md](/home/bd/gh/private-oke-karpenter/README.md:1)
- [gitops/c/kpo/pre-bootstrap-init.sh](/home/bd/gh/private-oke-karpenter/gitops/c/kpo/pre-bootstrap-init.sh:1)

## What To Measure

There are three different timing windows:

1. Karpenter scheduling and NodeClaim creation
2. OCI instance launch and node registration
3. Guest bootstrap and kubelet activation inside the node

Do not treat them as one opaque "startup time".

## Current NodePool Under Test

Default current NodePool:

- [gitops/c/kpo/nodepool.yaml](/home/bd/gh/private-oke-karpenter/gitops/c/kpo/nodepool.yaml:1)

Current defaults at the time this runbook was added:

- `NodePool`: `karpenter-general`
- capacity type: `on-demand`
- shape requirement: `VM.Standard.E3.Flex`

Important Ubuntu/KPO limitation confirmed on August 21, 2026:

- for Ubuntu OKE worker images, `imageFilter` is not a reliable selection path in the current KPO docs/behavior
- use `imageType: OKEImage` with an explicit `imageId` for the target Ubuntu image instead

## Pre-Checks

Before starting a timing run:

1. Verify KPO is healthy:

```bash
kubectl get pods -n karpenter -o wide
kubectl get application.argoproj.io -n argocd
```

2. Verify the active `NodePool` and `OCINodeClass`:

```bash
kubectl get nodepool
kubectl get ocinodeclass
kubectl get nodepool karpenter-general -o yaml
kubectl get ocinodeclass karpenter-general -o yaml
```

3. Check whether any Karpenter nodes already exist:

```bash
kubectl get nodes -L karpenter.sh/nodepool
kubectl get nodeclaims
```

4. If testing scale-from-zero, remove existing demand workloads first.

## Trigger A Clean Timing Event

Preferred clean benchmark:

- remove any existing `inflate` workload
- ensure there are no active `NodeClaim` objects
- use `make demand-single-node`

That target applies a single pod pinned to `karpenter.sh/nodepool=karpenter-general`, which avoids the baseline managed node and forces one Karpenter node without creating a multi-node burst.

```bash
make demand-delete
kubectl get nodeclaims
date -u --iso-8601=seconds
make demand-single-node
```

Use a larger burst workload only when you explicitly want a saturation or multi-node test.

Use a workload that definitely does not fit on the baseline node(s).

Record an explicit UTC start time:

```bash
date -u --iso-8601=seconds
```

Then create or scale the demand workload.

Example:

```bash
make demand-single-node
```

If `inflate` is not present, apply a test deployment that requests enough CPU or memory to force Karpenter provisioning.

## Outside View: Cluster And OCI Timing

### 1. Watch NodeClaims

```bash
kubectl get nodeclaims -w
```

Important timestamps to capture:

- first `NodeClaim` appears
- `NodeClaim` gets mapped to an OCI instance
- `NodeClaim` becomes associated with a Kubernetes node

### 2. Watch Nodes

```bash
kubectl get nodes -w
```

Important timestamps to capture:

- node first appears
- node reaches `Ready`

### 3. Watch The Workload Pod

```bash
kubectl get pods -o wide -w
```

Important timestamps to capture:

- pod scheduled
- pod enters `ContainerCreating`
- pod reaches `Running`

### 4. Inspect Events If It Is Slow

```bash
kubectl describe pod <pod-name>
kubectl describe nodeclaim <nodeclaim-name>
```

This usually tells you whether the delay was:

- no capacity / shape fallback
- instance not registering
- CNI delay
- image pull delay
- general bootstrap delay

## KPO Controller Timing Clues

KPO logs give the outside control-plane view.

```bash
kubectl logs -n karpenter deploy/karpenter --since=30m | rg 'created nodeclaim|launching oci instance|registered nodeclaim|initialized nodeclaim|all instance types exhausted|No Capacity'
```

Useful event meanings:

- `created nodeclaim`: Karpenter decided to provision
- `launching oci instance`: OCI launch request started
- `registered nodeclaim`: node object associated
- `initialized nodeclaim`: node became initialized from Karpenter's perspective

These markers are useful for:

- `NodeClaim created` -> `registered nodeclaim`
- `NodeClaim created` -> `initialized nodeclaim`

Current interpretation for this repo as of August 21, 2026:

- `NodeClaim created` -> `Launched` is mostly OCI/provider launch floor
- `Launched` -> `Registered` is the node join path
- `Registered` -> `Initialized` is now usually the OCI native pod networking readiness gate

## Inside View: Guest Bootstrap Timing

If the built worker image includes the baked timing monitor, gather:

```bash
journalctl -u oke-bootstrap-timing-monitor.service
cat /var/log/oke-optimized-bootstrap-timing.log
ls -1 /var/lib/oke-optimization
```

Expected markers from the current implementation in `oke-ubuntu-worker-node`:

- `monitor-start`
- `oke-installer-start`
- `oke-installer-end`
- `kubelet-active`
- `monitor-timeout` if bootstrap stalled

This is the guest-OS view and should be correlated with:

- `created nodeclaim`
- `registered nodeclaim`
- node `Ready`

## How To SSH For Node-Side Timing

If SSH key injection is enabled for the active `OCINodeClass`, connect to the Karpenter node and collect:

```bash
ssh ubuntu@<node-public-ip>
sudo journalctl -u oke.service
sudo journalctl -u kubelet
sudo journalctl -u oke-bootstrap-timing-monitor.service
sudo cat /var/log/oke-optimized-bootstrap-timing.log
```

If the node is Oracle Linux instead of Ubuntu, use the appropriate default user.

## Suggested Timing Report Format

For each run, record:

- test name
- date/time in UTC
- cluster version
- KPO chart or image version
- worker image name / OCID
- `NodePool` name
- `OCINodeClass` image config
- shape and size

Then capture:

- `t0`: workload submitted
- `t1`: first `NodeClaim` created
- `t2`: KPO log shows `launching oci instance`
- `t3`: node appears in Kubernetes
- `t4`: node becomes `Ready`

## August 20, 2026 Reference Result

Measured on the live Ubuntu 24.04 custom-image path in this repo:

- trigger time `t0`: `2026-08-20T11:23:19Z`
- first `NodeClaim` visible: about `+1s`
- first OCI instance visible in `NodeClaim`: about `+41s`
- first Kubernetes node object registered: about `+70s`
- first node `Ready=True`: about `+125s`

Observed node details:

- OS: `Ubuntu 24.04.4 LTS`
- kubelet: `v1.36.1`
- image OCID: `ocid1.image.oc1.eu-frankfurt-1.aaaaaaaaeqf6zbo5bjjh3lmqhxsj5trp5hx4bylvqynjosbkda3s5ad5qqea`

Important caveat:

- that measured run used an oversized burst deployment and Karpenter launched two nodes
- use `make demand-single-node` for a cleaner single-node benchmark on future runs

Clean single-node rerun on August 20, 2026:

- optimized image OCID:
  - `ocid1.image.oc1.eu-frankfurt-1.aaaaaaaab4homejprcl3ukkbyjuzap6zup5akptchq4jbzygryi75u6swt7q`
- measured before removing the synthetic startup-taint helper:
  - `NodeClaim created`: `2026-08-20T14:27:29Z`
  - `Launched=True`: `2026-08-20T14:28:01Z`
  - `Registered=True`: `2026-08-20T14:28:35Z`
  - `Initialized=True`: `2026-08-20T14:29:17Z`
  - workload pod `Running`: `2026-08-20T14:29:19Z`
  - breakdown:
    - claim -> launch: `32s`
    - launch -> register: `34s`
    - register -> initialized: `42s`
    - claim -> initialized: `108s`
    - claim -> pod running: `110s`

Follow-up change on August 20, 2026:

- removed `startupTaints` from `gitops/c/kpo/nodepool.yaml`
- removed the `cni-ready-untaint` helper from `gitops/c/kpo/kustomization.yaml`
- reason:
  - that helper path moved Karpenter `Initialized=True` later than the earlier `~98s` result and was introducing a synthetic orchestration delay on top of node bootstrap

Clean rerun after removing the startup-taint helper:

- `NodeClaim created`: `2026-08-20T14:35:57Z`
- `Launched=True`: `2026-08-20T14:36:29Z`
- `Registered=True`: `2026-08-20T14:37:05Z`
- `Initialized=True`: `2026-08-20T14:37:42Z`
- node `Ready=True`: `2026-08-20T14:37:42Z`
- workload pod `Running`: `2026-08-20T14:37:57Z`
- breakdown:
  - claim -> launch: `32s`
  - launch -> register: `36s`
  - register -> initialized: `37s`
  - claim -> initialized: `105s`
  - claim -> pod running: `120s`

Clean single-node rerun on August 21, 2026 with the `ubuntu-24.04-2026.08.21.1-OKE-1.36.1-cni-preseed` image:

- `t0`: `2026-08-21T08:01:05Z`
- `NodeClaim created`: `2026-08-21T08:01:08Z`
- OCI launch request started: `2026-08-21T08:01:08Z`
- OCI instance launched: `2026-08-21T08:01:40Z`
- `NodeClaim Registered=True`: `2026-08-21T08:02:22Z`
- `NodeClaim Initialized=True`: `2026-08-21T08:02:24Z`
- workload pod scheduled: `2026-08-21T08:02:23Z`
- workload pod container started: `2026-08-21T08:03:04Z`
- breakdown:
  - demand -> claim: `3s`
  - claim -> launch: `32s`
  - claim -> register: `74s`
  - claim -> initialized: `76s`
  - demand -> pod running: `119s`

Guest-side timing proof from the same node:

- `monitor-start`: `2026-08-21T08:02:11Z`
- `oke-installer-start`: `2026-08-21T08:02:12Z`
- `cri-runtime-active`: `2026-08-21T08:02:20Z`
- `oke-installer-end`: `2026-08-21T08:02:22Z`
- `kubelet-active`: `2026-08-21T08:02:22Z`

Residual bottleneck proof from the same run:

- pod sandbox creation still failed twice with `plugin type="oci-ipvlan" failed (add): unable to allocate IP address`
- preseeded OCI CNI binaries were present from image bake time, but `/etc/cni/net.d/10-oci.conflist` was still rewritten on-node at about `2026-08-21T08:02:54Z`
- this materially improved `NodeClaim -> Ready`, but did not remove the OKE native pod-networking delay for the first workload

Mitigated rerun after fixing the `cni-ready-untaint` helper RBAC on August 21, 2026:

- startup taint used:
  - `oke.oraclecloud.com/cni-not-ready:NoSchedule`
- behavior:
  - workloads stayed `Pending` until the node-side `vcn-native-ip-cni` pod was fully ready
  - after the helper could read `kube-system` pods, it removed the startup taint and the workload scheduled cleanly
- measured handoff after the helper fix:
  - pending workload -> pod nominated: about `58s`
  - pending workload -> `NodeClaim Initialized=True`: about `79s`
  - pending workload -> pod scheduled: about `79s`
  - pending workload -> pod container started: about `81s`
- important difference from the earlier run:
  - no fresh `FailedCreatePodSandBox`
  - no fresh `plugin type="oci-ipvlan" failed (add): unable to allocate IP address`

## Control Boundary

Treat the startup path as three separate buckets:

1. Provider floor

- `NodeClaim created` -> `Launched=True`
- mostly OCI-side work:
  - instance launch work request
  - VNIC and boot-volume provisioning
  - early native pod networking control-plane setup
- this repo can avoid regressions here, but cannot materially optimize the floor

2. Guest bootstrap

- guest `monitor-start` / `oke-installer-start` -> `kubelet-active`
- this is the Ubuntu image and bootstrap path controlled by:
  - the custom image build
  - the Ubuntu bootstrap shim
  - image-time pre-pull / preseed decisions
- this repo materially improved this bucket

3. Post-bootstrap CNI gate

- `Registered=True` / `Ready=True` -> first workload pod sandbox and first workload `Running`
- underlying OCI native pod networking timing is mostly provider behavior
- this repo can mitigate the user-visible failure mode with startup taints and explicit untaint logic
- this repo cannot fully eliminate the OCI-side IPAM / NPN convergence floor

Guest-side timing proof from a fresh node on August 20, 2026:

- `monitor-start`: `2026-08-20T14:41:54Z`
- `oke-installer-start`: `2026-08-20T14:41:54Z`
- `cri-runtime-active`: `2026-08-20T14:41:58Z`
- `oke-installer-end`: `2026-08-20T14:42:03Z`
- `kubelet-active`: `2026-08-20T14:42:03Z`

Interpretation:

- the custom Ubuntu image bootstrap is no longer the dominant delay
- the remaining large gap is after kubelet activation and after node registration
- fresh-node evidence showed `vcn-native-ip-cni` as the main floor:
  - pod created: `2026-08-20T14:42:02Z`
  - pod ready: `2026-08-20T14:42:44Z`
  - host CNI config file `10-oci.conflist` written at `2026-08-20T14:42:42Z`
  - kubelet reported pod-sandbox failures during this window, including `unable to allocate IP address`

Current conclusion as of August 20, 2026:

- image-level optimization recovered the worker bootstrap path from the earlier broken rebuild and materially improved bootstrap timing
- removing the synthetic startup-taint helper recovered some Karpenter-side regression
- the next meaningful startup improvement is likely in the OKE native pod networking bring-up path, not in the Ubuntu image build itself

- `t0`: `2026-08-20T11:32:27Z`
- `NodeClaim created`: `2026-08-20T11:32:30Z`
- OCI launch work request complete: `2026-08-20T11:33:13Z`
- node registered: `2026-08-20T11:33:38Z`
- node `Ready=True`: `2026-08-20T11:34:26Z`

Observed bottleneck from live node-side evidence:

- image-side `oke bootstrap` finished quickly:
  - `oke-installer-start`: `2026-08-20T11:33:31Z`
  - `oke-installer-end`: `2026-08-20T11:33:40Z`
  - `kubelet-active`: `2026-08-20T11:33:40Z`
- the remaining delay was dominated by node-side OKE add-on and VCN Native IP readiness:
  - `NodeClaim Registered=True` at `11:33:38Z`
  - `NodeClaim Initialized=True` at `11:34:28Z`
  - `vcn-native-ip-cni` init restarted once and only completed at `11:34:26Z`
  - the first workload hit `FailedCreatePodSandBox ... unable to allocate IP address` right as the node first became `Ready`

Interpretation:

- current bottleneck is not Ubuntu package install or `/usr/bin/oke bootstrap`
- current bottleneck is the `Registered -> Ready` and immediate post-`Ready` VCN Native IP / daemonset convergence window
- `t5`: pod becomes `Running`

Derived metrics:

- scheduler delay: `t1 - t0`
- OCI launch-to-node delay: `t3 - t2`
- node ready delay: `t4 - t3`
- pod start delay after node ready: `t5 - t4`
- total workload startup time: `t5 - t0`

If guest markers are available, also capture:

- `oke-installer-start`
- `oke-installer-end`
- `kubelet-active`

This lets you answer:

- was the slowdown before instance launch?
- inside node bootstrap?
- after node registration due to image pulls or kube-system startup?

## Compare Baseline vs Optimized

Use the same:

- workload
- requests/limits
- region
- shape
- subnet layout
- KPO configuration

Change only one variable at a time:

- worker image
- bootstrap script
- registry / image source
- pre-pulled image set

Otherwise the timing comparison is not trustworthy.

## Common Failure Modes To Note Separately

- `all instance types exhausted due to insufficient capacity`
- `NodeClaim` remains `Unknown`
- node created but not `Ready`
- pod stuck in `ContainerCreating`
- CNI or secondary-VNIC allocation failures

These should be logged as failure categories, not averaged into "startup time".

## Minimal Repeatable Command Set

```bash
date -u --iso-8601=seconds
kubectl get nodeclaims -w
kubectl get nodes -w
kubectl get pods -o wide -w
kubectl logs -n karpenter deploy/karpenter --since=30m | rg 'created nodeclaim|launching oci instance|registered nodeclaim|initialized nodeclaim'
```

## Practical Conclusion

For this repo, the most useful baseline timing comparison is:

1. current image + current bootstrap path
2. optimized image + same bootstrap path

Only after that should you compare:

3. optimized image + redesigned runtime bootstrap

That keeps the experiment honest and shows which improvement actually moved the needle.
