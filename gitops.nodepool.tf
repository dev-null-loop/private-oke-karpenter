locals {
  nodepool = {
    capacityType  = var.karpenter.capacityType
    instanceShape = var.karpenter.instanceShape
    limitCpu      = var.karpenter.limits.cpu
    limitMemory   = var.karpenter.limits.memory
  }
}

resource "local_file" "gitops_nodepool" {
  filename = "${path.module}/gitops/c/kpo/nodepool.yaml"
  content  = templatefile("${path.module}/gitops/c/kpo/nodepool.yaml.tftpl", local.nodepool)
}
