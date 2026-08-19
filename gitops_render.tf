locals {
  values_yaml = {
    clusterCompartmentId = var.compartment_ids[var.karpenter.cluster_compartment]
    vcnCompartmentId     = var.compartment_ids[var.subnets[var.karpenter.node_subnet].compartment]
    serviceAccountName   = var.karpenter.iam.service_account
    apiserverEndpoint = split(
      ":",
      coalesce(
        module.clusters[var.karpenter.cluster].endpoints[0].private_endpoint,
        module.clusters[var.karpenter.cluster].endpoints[0].kubernetes,
      )
    )[0]
  }

  ocinodeclass_yaml = {
    primaryVnicSubnetId       = module.subnets[var.karpenter.node_subnet].id
    secondaryVnicSubnetId     = module.subnets[var.karpenter.pod_subnet].id
    primaryVnicAssignPublicIp = var.karpenter.assign_public_ip
    useImageFilter            = var.karpenter.image_filter != null
    imageId                   = try(var.oke_worker_node_image_ids[var.karpenter.node_image], "")
    imageFilterCompartmentId  = var.karpenter.image_filter != null ? var.compartment_ids[coalesce(try(var.karpenter.image_filter.compartment, null), var.karpenter.cluster_compartment)] : ""
    imageFilterOs             = var.karpenter.image_filter != null ? var.karpenter.image_filter.os : ""
    imageFilterOsVersion      = var.karpenter.image_filter != null ? var.karpenter.image_filter.os_version : ""
    preBootstrapInitScript    = filebase64("${path.module}/gitops/c/kpo/pre-bootstrap-init.sh")
    shapeConfigOcpus          = 4
    shapeConfigMemoryInGbs    = 16
  }
}

resource "local_file" "gitops_kpo_values" {
  filename = "${path.module}/gitops/c/kpo/values.yaml"
  content  = templatefile("${path.module}/gitops/c/kpo/values.yaml.tftpl", local.values_yaml)
}

resource "local_file" "gitops_kpo_ocinodeclass" {
  filename = "${path.module}/gitops/c/kpo/ocinodeclass.yaml"
  content  = templatefile("${path.module}/gitops/c/kpo/ocinodeclass.yaml.tftpl", local.ocinodeclass_yaml)
}
