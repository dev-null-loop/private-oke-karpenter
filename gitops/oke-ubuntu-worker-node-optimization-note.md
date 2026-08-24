# OKE Ubuntu Worker Node Optimization Note

Date: August 21, 2026

Scope:

- image build repo: `/home/bd/gh/oke-ubuntu-worker-node`
- KPO/GitOps repo: `/home/bd/gh/private-oke-karpenter`

Goal:

- reduce Karpenter-on-OKE Ubuntu worker startup time
- separate OCI provider floor from guest bootstrap time
- eliminate first-workload failures during native pod networking convergence

## Optimizations Performed

### 1. Switched to a custom Ubuntu OKE worker image

- built and used a custom Ubuntu 24.04 image instead of relying only on the stock path
- kept Ubuntu-specific bootstrap compatibility through `metadata.user_data`

Files:

- `/home/bd/gh/oke-ubuntu-worker-node/packer/image.pkr.hcl`
- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/ocinodeclass.yaml`
- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/pre-bootstrap-init.sh`

### 2. Fixed Ubuntu bootstrap argument handling

- added a custom Ubuntu bootstrap shim that translates the KPO metadata contract into the Ubuntu `oke bootstrap` CLI contract
- used:
  - `apiserver_host`
  - `cluster_ca_cert`
  - `kubelet-extra-args`
  - `kubedns_svc_ip`

Result:

- removed earlier bootstrap failures caused by mismatched Oracle Linux vs Ubuntu argument assumptions

### 3. Added image-time helper packages and timing instrumentation

- baked in:
  - `jq`
  - `curl`
  - `crictl`
- added `oke-bootstrap-timing-monitor.service`
- wrote guest timing to:
  - `/var/log/oke-optimized-bootstrap-timing.log`

Result:

- made it possible to measure:
  - monitor start
  - OKE bootstrap start/end
  - CRI runtime active
  - kubelet active

### 4. Enabled image pre-pull for first-node hot-path images

- enabled image-time pre-pull in the custom image
- baked these hot-path images:
  - `oke-public-vcn-native-ip-cni-plugin`
  - `oke-public-cloud-provider-oci`
  - `oke-public-kube-proxy`
  - `oke-public-proxymux-cli`
  - `public.ecr.aws/z2c7x8q5/bitnami/kubectl`

Result:

- removed repeated first-node image pull cost from the critical startup path

### 5. Enabled earlier CRI runtime startup

- enabled `crio.service` in the image

Result:

- reduced time-to-runtime availability after first boot

### 6. Pre-created CNI host paths

- pre-created:
  - `/opt/cni/bin`
  - `/etc/cni/net.d`
  - `/etc/oci-cni`
  - `/run/xtables.lock`

Result:

- removed some first-boot filesystem preparation from the hot path

### 7. Pre-seeded OCI CNI host assets at image build time

- extracted OCI CNI binaries from the pre-pulled plugin image into the host image:
  - `oci-ipam`
  - `oci-ipvlan`
  - `oci-ptp`
- baked the base OCI CNI config files:
  - `/etc/cni/net.d/10-oci.conflist`
  - `/etc/cni/net.d/99-dummy.conf`
  - `/etc/oci-cni/cni-conf.json`
  - `/etc/oci-cni/iptables`
  - `/etc/oci-cni/ip6tables`

Result:

- materially improved `NodeClaim -> Ready`
- did not fully remove OCI native pod networking convergence time

### 8. Removed the earlier synthetic startup-taint path when it was shown to add delay

- tested an earlier helper path for startup taint removal
- removed it after proving it added orchestration delay without solving the real OCI CNI convergence issue

Result:

- recovered some Karpenter-side time

### 9. Corrected Ubuntu image selection in KPO

- confirmed that Ubuntu images should use:
  - `imageType: OKEImage`
  - explicit `imageId`
- confirmed `imageFilter` was not reliable for this Ubuntu path
- avoided unsupported `imageType: Custom`

Result:

- ensured KPO could actually launch the intended optimized Ubuntu images

### 10. Added a startup-taint mitigation for OCI CNI convergence

- reintroduced a startup taint on the `NodePool`:
  - `oke.oraclecloud.com/cni-not-ready:NoSchedule`
- added `cni-ready-untaint` helper logic to remove the taint only when the node-local `vcn-native-ip-cni` pod is fully ready

Files:

- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/nodepool.yaml`
- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/nodepool.yaml.tftpl`
- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/cni-ready-untaint.yaml`
- `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/kustomization.yaml`

### 11. Fixed the startup-taint helper RBAC bug

- the helper initially could patch nodes but could not read pods in `kube-system`
- added RBAC permissions for pod `get/list`

Result:

- the helper could finally observe `vcn-native-ip-cni` readiness and remove the startup taint correctly
- eliminated the first-workload `FailedCreatePodSandBox` / `oci-ipvlan ... unable to allocate IP address` failure mode

### 12. Tested lowering pod-subnet `ipCount`

- tried reducing `secondaryVnicConfigs[*].ipCount`

Outcome:

- `2` was too small for the current pod envelope
- `5` was invalid because OCI requires a power-of-two count
- restored `8`

Result:

- no viable optimization there for the current node profile

### 13. Disabled wait-online services and moved the timing monitor earlier

- masked:
  - `systemd-networkd-wait-online.service`
  - `NetworkManager-wait-online.service`
- moved the timing monitor earlier:
  - `After=basic.target`
  - `Before=network-online.target oke.service kubelet.service`

Result:

- produced a new image variant to test whether part of the pre-kubelet gap was guest-side wait-online delay
- yielded a modest improvement in `NodeClaim -> Registered`

## Measured Results

### Earlier clean optimized run

- `NodeClaim -> Ready`: about `76s`
- demand -> workload container started: about `119s`

### Startup-taint mitigation after RBAC fix

- pending workload -> scheduled: about `79s`
- pending workload -> container started: about `81s`
- no fresh sandbox/IP allocation failures during the handoff

### Latest wait-online image run

Using image:

- `ocid1.image.oc1.eu-frankfurt-1.aaaaaaaagzcvrwr32m6z2aiey25j462qvepeto4r6pqv245mbx2zaienodhq`

Cluster-side timing:

- `NodeClaim created`: `2026-08-21T09:54:22Z`
- `Launched=True`: `2026-08-21T09:54:54Z`
- `Registered=True`: `2026-08-21T09:55:28Z`
- node object `Ready=True`: `2026-08-21T09:55:28Z`
- `Initialized=True`: `2026-08-21T09:56:08Z`
- workload pod scheduled: `2026-08-21T09:56:08Z`
- workload container started: `2026-08-21T09:56:11Z`

Breakdown:

- claim -> launch: `32s`
- claim -> registered: `66s`
- claim -> node Ready/joined: `66s`
- claim -> initialized/workload schedulable: `106s`
- claim -> workload container started: `109s`
- demand -> workload container started: `112s`

## Current Conclusion

What we optimized successfully:

- guest Ubuntu bootstrap
- image-time hot-path preparation
- OCI CNI asset preseed
- first-workload race mitigation
- wait-online appears to offer a modest improvement in the pre-registration path
- latest rebuild reduced the node-join path by about `8s` versus the earlier `74s` registered run

What is still mostly outside repo control:

- `NodeClaim -> Launched` OCI/provider floor
- much of the early instance/network provisioning path
- much of the remaining `Registered -> Initialized` OCI native pod networking convergence

Practical boundary at this point:

- node join is now in the `~66s` class
- first real workload start is still in the `~109s` to `~119s` class because the node waits for OCI CNI readiness before becoming schedulable
- further large improvements likely require OCI/KPO/CNI product-side changes rather than more local repo tuning
