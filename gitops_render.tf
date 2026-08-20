locals {
  karpenter_image_type       = try(var.karpenter.image_type, "OKEImage")
  karpenter_bootstrap_mode   = try(var.karpenter.bootstrap_mode, "prebootstrap")
  karpenter_controller_image = try(var.karpenter.controller_image, null)

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
    useControllerImageOverride = local.karpenter_controller_image != null
    controllerImageRegistry    = local.karpenter_controller_image != null ? local.karpenter_controller_image.registry : ""
    controllerImageRepository  = local.karpenter_controller_image != null ? local.karpenter_controller_image.repository_name : ""
    controllerImageTag         = local.karpenter_controller_image != null ? local.karpenter_controller_image.tag : ""
    useControllerPullSecret    = local.karpenter_controller_image != null && try(local.karpenter_controller_image.pull_secret_name, null) != null
    controllerPullSecretName   = local.karpenter_controller_image != null ? try(local.karpenter_controller_image.pull_secret_name, "") : ""
  }

  ocinodeclass_yaml = {
    primaryVnicSubnetId       = module.subnets[var.karpenter.node_subnet].id
    secondaryVnicSubnetId     = module.subnets[var.karpenter.pod_subnet].id
    primaryVnicAssignPublicIp = var.karpenter.assign_public_ip
    imageType                 = local.karpenter_image_type
    useImageFilter            = var.karpenter.image_filter != null
    imageId                   = try(var.oke_worker_node_image_ids[var.karpenter.node_image], "")
    imageFilterCompartmentId  = var.karpenter.image_filter != null ? var.compartment_ids[coalesce(try(var.karpenter.image_filter.compartment, null), var.karpenter.cluster_compartment)] : ""
    imageFilterOs             = var.karpenter.image_filter != null ? var.karpenter.image_filter.os : ""
    imageFilterOsVersion      = var.karpenter.image_filter != null ? var.karpenter.image_filter.os_version : ""
    usePreBootstrapInitScript = local.karpenter_bootstrap_mode == "prebootstrap"
    preBootstrapInitScript    = local.karpenter_bootstrap_mode == "prebootstrap" ? filebase64("${path.module}/gitops/c/kpo/pre-bootstrap-init.sh") : ""
    useMetadataUserData       = local.karpenter_bootstrap_mode == "metadata"
    metadataUserData          = local.karpenter_bootstrap_mode == "metadata" ? base64encode(templatefile("${path.module}/gitops/c/kpo/metadata-user-data-ubuntu.yaml.tftpl", {})) : ""
    shapeConfigOcpus          = 8
    shapeConfigMemoryInGbs    = 32
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
