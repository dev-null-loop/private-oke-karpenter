# Ubuntu OKE Image Notes

Date captured:

- August 18, 2026

Purpose:

- record what was learned from direct inspection of Ubuntu OKE worker image artifacts
- separate "base Ubuntu image" from "Ubuntu image already converted into an OKE worker image"
- document why custom Ubuntu worker-image work is currently blocked in this environment

## Images Inspected

Local image artifacts in:

- `/home/bd/iso`

Inspected files:

- `ubuntu-amd64-minimal-22.04-jammy-v20250604.1-OKE-1.31.1.img`
- `ubuntu-amd64-minimal-22.04-jammy-v20250604.1-OKE-1.32.1.img`

Both files are:

- QCOW2 disk images
- not ISOs
- already pre-baked OKE worker images

## High-Level Conclusion

These Ubuntu images are not just plain Ubuntu plus a runtime cloud-init snippet.

They are already transformed into OKE worker images by baking in:

- an OKE-specific Ubuntu apt repository
- preinstalled OKE/Kubernetes/CRI-O packages
- an OKE bootstrap systemd unit that runs before kubelet
- the Oracle `oci-oke-node-client` bootstrap binary and related tooling

The practical conversion mechanism from plain Ubuntu to Ubuntu OKE worker image is:

1. add the OKE-specific Ubuntu apt repo for the target Kubernetes line
2. install the OKE worker package stack
3. install and enable the `oke.service` bootstrap unit
4. boot the image and let `/usr/bin/oke bootstrap` configure the node before kubelet starts

## Exact Evidence From The Images

### 1. OKE-specific apt repositories are baked in

In the `1.31.1` image:

- `/etc/apt/sources.list.d/cloud-images-oke-ppa.list`

contains:

```text
deb https://ppa.launchpadcontent.net/cloud-images/oke-1.31/ubuntu jammy main
```

In the `1.32.1` image:

- `/etc/apt/sources.list.d/cloud-images-oke-ppa.list`

contains:

```text
deb https://ppa.launchpadcontent.net/cloud-images/oke-1.32/ubuntu jammy main
```

This means the image is tied to a Kubernetes/OKE minor line through a dedicated package channel.

### 2. OKE bootstrap is installed as a systemd unit

File:

- `/lib/systemd/system/oke.service`

Contents:

```ini
[Unit]
Description=Oracle Container Engine for Kubernetes worker node configuration
After=network-online.target
Before=kubelet.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/bin/oke bootstrap $OKE_EXTRA_ARGS
TimeoutSec=1800

[Install]
WantedBy=multi-user.target
Alias=proxymux-certs.service oci-oke-node-bootstrap.service
```

This is the main control point that turns the machine into an OKE worker node at boot.

### 3. The OKE package stack is preinstalled

The inspected images include these relevant packages.

For `1.31.1`:

- `cloud-init` `24.4.1-0ubuntu0~22.04.2`
- `containernetworking-plugins` `1.3.0-0ubuntu0~oke1.29.0~22.04.1`
- `cri-o` `1.31.6-oke1.31.1~22.04.2`
- `cri-o-runc` `1.1.13-oke1.31.1~22.04`
- `kubelet` `1.31.1-oke1.31.1~22.04`
- `oci-oke-node-client` `2.0.0-74.87980f6fe32`
- `oke-meta` `1.31.1-oke1.31.0~22.04`

For `1.32.1`:

- `cloud-init` `24.4.1-0ubuntu0~22.04.2`
- `containernetworking-plugins` `1.3.0-0ubuntu0~oke1.29.0~22.04.1`
- `cri-o` `1.32.0-oke1.32.1~22.04.3`
- `cri-o-runc` `1.2.1-oke1.32.1~22.04`
- `kubelet` `1.32.1-oke1.32.1~22.04.12`
- `oci-oke-node-client` `2.0.0-74.87980f6fe32`
- `oke-meta` `1.32.1-oke1.32.0~22.04`

Interpretation:

- `oci-oke-node-client` is the Oracle-specific bootstrap/client layer
- `oke-meta` is the metapackage that pulls the node runtime stack together
- `kubelet`, `cri-o`, and related packages are OKE-aligned builds

### 4. `oci-oke-node-client` is the package that lays down the bootstrap machinery

The package file list includes:

- `/usr/bin/oke`
- `/usr/bin/node-doctor.sh`
- `/usr/lib/systemd/system/oke.service`
- `/usr/lib/systemd/system-preset/30-oke.preset`
- `/etc/oke`
- `/etc/proxymux`
- `/usr/lib/sysctl.d/98-oke.conf`

Its post-install script does the following on initial installation:

- disables swap
- disables `irqbalance`
- disables `netfilter-persistent`
- disables `firewalld`
- disables `ufw`
- flushes iptables
- links `/usr/bin/oke` to:
  - `/usr/bin/proxymux-client`
  - `/usr/bin/oci-oke-node-client`
- applies sysctl config
- loads `br_netfilter`
- installs bash completion for `oke`

This is image mutation at package-install time, not just runtime cloud-init.

### 5. Kubelet is wired to CRI-O in the image

File:

- `/etc/sysconfig/kubelet`

Contents in both images:

```bash
KUBELET_EXTRA_ARGS="--fail-swap-on=false"
KUBELET_CRIO_ARGS="--container-runtime-endpoint=unix:///var/run/crio/crio.sock --runtime-request-timeout=10m"
```

That confirms the image is preconfigured for the expected OKE runtime stack.

## What This Means For Custom Ubuntu Images

If we ever build a custom Ubuntu image intended to behave like an Ubuntu OKE worker image, the minimum required mechanism is:

1. start from a usable Ubuntu base image compatible with OKE expectations
2. add the OKE Ubuntu package repo matching the target Kubernetes/OKE line
3. install the OKE package stack:
   - `oci-oke-node-client`
   - `oke-meta`
   - `kubelet`
   - `cri-o`
   - `cri-o-runc`
   - `containernetworking-plugins`
4. ensure `oke.service` is present and enabled
5. preserve cloud-init and boot-time ability to run `oke bootstrap`

Operationally, the bootstrap flow is:

- machine boots
- `oke.service` runs `/usr/bin/oke bootstrap`
- node bootstrap completes before `kubelet` starts
- kubelet runs against CRI-O and the node joins the cluster

## Important Current Blocker

Even though the conversion mechanism is now understood, this repo should explicitly remember:

- we do not currently have usable Ubuntu OKE base-image access in this tenancy/region
- OKE `node-pool-options` in this environment did not expose any `ubuntu-*` worker images
- therefore we currently cannot execute the "build custom Ubuntu OKE worker image" path end-to-end here

So the current state is:

- KPO code path for `imageType: Custom` + explicit `metadata.user_data` is patched and usable in principle
- but the upstream Ubuntu OKE image-access dependency is still blocked in this environment

## Related Notes

See also:

- `gitops/custom-kpo-image.md`

That runbook explains how to build and deploy a custom KPO controller image. This note is different: it explains how Ubuntu OKE worker images themselves are composed.
