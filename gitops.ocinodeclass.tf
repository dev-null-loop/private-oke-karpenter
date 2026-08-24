locals {
  ocinodeclass = {
    primaryVnicSubnetId       = module.subnets[var.karpenter.node_subnet].id
    secondaryVnicSubnetId     = module.subnets[var.karpenter.pod_subnet].id
    primaryVnicAssignPublicIp = var.karpenter.assign_public_ip
    shapeOcpus                = var.karpenter.shape.ocpus
    shapeMemoryInGbs          = var.karpenter.shape.memory_in_gbs
    podIpCount                = var.karpenter.pod_ip_count
    imageType                 = var.karpenter.image_type
    imageSource               = var.karpenter.image_source
    imageId                   = try(var.oke_worker_node_image_ids[var.karpenter.node_image], "")
    imageFilterCompartmentId  = lookup(var.compartment_ids, coalesce(try(var.karpenter.image_filter.compartment, null), var.karpenter.cluster_compartment), null)
    imageFilterOs             = var.karpenter.image_filter == null ? null : var.karpenter.image_filter.os
    imageFilterOsVersion      = var.karpenter.image_filter == null ? null : var.karpenter.image_filter.os_version
    bootstrapMode             = var.karpenter.bootstrap_mode
    preBootstrapInitScript    = filebase64("${path.module}/gitops/c/kpo/pre-bootstrap-init.sh")
    metadataUserData          = base64encode(templatefile("${path.module}/gitops/c/kpo/metadata-user-data-ubuntu.yaml.tftpl", {}))
  }
}

resource "local_file" "gitops_ocinodeclass" {
  filename = "${path.module}/gitops/c/kpo/ocinodeclass.yaml"
  content  = templatefile("${path.module}/gitops/c/kpo/ocinodeclass.yaml.tftpl", local.ocinodeclass)
}
