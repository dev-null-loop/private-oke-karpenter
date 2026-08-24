locals {
  values = {
    clusterCompartmentId = var.compartment_ids[var.karpenter.cluster_compartment]
    vcnCompartmentId     = var.compartment_ids[var.subnets[var.karpenter.node_subnet].compartment]
    serviceAccountName   = var.karpenter.iam.service_account
    apiserverEndpoint = split(
      ":",
      coalesce(
        module.clusters[var.karpenter.cluster].private_endpoint,
        module.clusters[var.karpenter.cluster].kubernetes_endpoint,
      )
    )[0]
    controllerImageRegistry   = try(var.karpenter.controller_image.registry, "")
    controllerImageRepository = try(var.karpenter.controller_image.repository_name, "")
    controllerImageTag        = try(var.karpenter.controller_image.tag, "")
    controllerPullSecretName  = try(var.karpenter.controller_image.pull_secret_name, "")
  }
}

resource "local_file" "gitops_values" {
  filename = "${path.module}/gitops/c/kpo/values.yaml"
  content  = templatefile("${path.module}/gitops/c/kpo/values.yaml.tftpl", local.values)
}
