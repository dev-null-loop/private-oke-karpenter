The GitHub issue is basically this:

Karpenter is doing its job and asking OCI for new nodes because the workload pods are pending. OCI does create the VM instances. But with OCI VCN-native pod networking, a new node is not usable just because the VM exists. OCI also needs to reserve pod IP space for that node by carving out a contiguous block of addresses in the pod subnet.

In this case, the configuration is telling OCI to use the same subnet for both nodes and pods, and to reserve a fairly large pod-IP block per node (`secondary_vnic_ip_count = 32`). OCI tries to allocate that as a contiguous chunk, effectively a `/27`. The subnet may still have free IPs overall, but if those free IPs are fragmented rather than available as one continuous range, the allocation fails.

So the failure pattern looks confusing at first:
- Karpenter creates `NodeClaim`s
- OCI launches the instances
- pods are nominated to those future nodes
- but the nodes never register in Kubernetes

The reason they never register is that OCI cannot finish the Native Pod Network setup for those nodes. The key error is `CreatePrivateIPFailed` with “not enough capacity for allocating cidr of length 27”. That does not mean “zero free IPs”; it means “no sufficiently large contiguous block exists”.

The practical takeaway is:
- this is not primarily a Karpenter bug in the sense of “Karpenter didn’t launch nodes”
- it is an OCI networking allocation constraint exposed by the way Karpenter is asking for pod capacity
- the usual fix is to use separate pod subnet(s), larger pod subnet(s), or smaller per-node pod-IP allocations

That is why the issue can happen “even though the subnet still has free IPs”. The missing detail is contiguous space, not total space.
