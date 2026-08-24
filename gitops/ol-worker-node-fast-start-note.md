# Oracle Linux Worker Node Fast-Start Note

Date: August 23, 2026

Context:

- customer uses Karpenter on OKE with standard Oracle Linux 8 OKE images
- shapes include large VM shapes and bare metal fallback
- reported timing is about 3 minutes from `NodeClaim` creation to node `Ready`

Customer note:

- preferred shapes: `E5` or `E6`
- fallback shape: `BM.Standard3`
- example node size: `64` OCPU / `256` GB RAM

Observed path from the note:

1. Karpenter creates a `NodeClaim`
2. OCI launches the compute instance
3. the node joins the cluster
4. the node is not yet `Ready`
5. images are downloaded and `kube-system` pods come up
6. the node eventually becomes `Ready`

Assessment in the current fast-start context:

1. the reported `~3 minutes` is plausible for stock OKE images with no image-side optimization
2. the note correctly separates launch time from post-launch bootstrap time
3. bare metal is likely slower than VM shapes on the launch side
4. very large shapes can also increase placement and launch variance
5. image-side optimization can reduce the post-launch portion, but not the OCI launch floor

Relevant comparison to the Ubuntu fast-start work:

1. the Ubuntu work reduced time by moving first-boot work into the image
2. the same general optimization surfaces exist for Oracle Linux worker nodes:
   - install OKE node packages at image build time
   - pre-pull first-boot and first-pod-path images
   - pre-seed OCI CNI host assets
   - remove unnecessary first-boot work
   - enable the runtime early
   - add timing instrumentation
3. those optimizations do not remove:
   - OCI instance launch time
   - shape placement delay
   - bare metal launch overhead
   - native pod networking convergence after registration

Can the same be done for Oracle Linux worker nodes?

1. yes, in principle
2. the same fast-start image pattern should apply to Oracle Linux OKE worker images
3. this may be simpler than Ubuntu because KPO already expects the Oracle Linux bootstrap contract
4. Ubuntu required a bootstrap compatibility shim; Oracle Linux may not need that extra layer

About `preBootstrapInitScript`:

1. it is an `OCINodeClass` field used by KPO to run a script on the instance before normal bootstrap completes
2. it is suitable for small host preparation tasks on the boot path
3. typical examples:
   - filesystem growth
   - directory creation
   - ownership or permission fixes
   - small bootstrap compatibility setup
4. because it runs on every node boot, it is on the critical path to `Ready`

Customer example:

```bash
sudo /usr/libexec/oci-growfs -y
mkdir -p /var/log/pplogger
chown -R 1000:000 /var/log/pplogger
```

Interpretation:

1. `oci-growfs -y` expands the root filesystem to use the full boot volume
2. `mkdir -p /var/log/pplogger` creates an application log directory
3. `chown -R 1000:000 /var/log/pplogger` sets ownership for that workload
4. the directory and ownership steps are negligible
5. `oci-growfs` adds some boot-path work, but by itself is unlikely to explain a full 3-minute startup

Current KPO usage in this workspace:

1. `private-oke-karpenter` already uses `preBootstrapInitScript`
2. current use is mainly Ubuntu bootstrap compatibility, not application preparation
3. file:
   - `/home/bd/gh/private-oke-karpenter/gitops/c/kpo/pre-bootstrap-init.sh`
4. that script creates `/etc/oke/oke-install.sh` as a wrapper so KPO's Oracle-Linux-oriented bootstrap contract can call Ubuntu's `/usr/bin/oke bootstrap`

Practical conclusion:

1. the customer note is consistent with the optimization model already used for Ubuntu
2. Oracle Linux worker nodes should have the same main image-side optimization surfaces
3. the biggest residual floor may still be OCI launch time, especially for `BM.Standard3`
4. `preBootstrapInitScript` should stay minimal because it is boot-path work

Resume points:

1. decide whether to create a separate Oracle Linux image-builder repo or make the current image builder support both Ubuntu and Oracle Linux
2. inspect the Oracle Linux OKE bootstrap/package contract before implementing anything
3. identify the standard Oracle Linux first-boot image set for pre-pull
4. verify whether Oracle Linux can avoid the Ubuntu-specific bootstrap shim entirely
