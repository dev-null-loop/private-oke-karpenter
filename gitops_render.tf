locals {
  values_yaml = {
    clusterCompartmentId = var.compartment_ids[var.karpenter.cluster_compartment]
    vcnCompartmentId     = var.compartment_ids[var.subnets["nodes"].compartment]
    apiserverEndpoint = split(
      ":",
      coalesce(
        module.clusters[var.karpenter.cluster].endpoints[0].private_endpoint,
        module.clusters[var.karpenter.cluster].endpoints[0].kubernetes,
      )
    )[0]
  }

  ocinodeclass_yaml = {
    primaryVnicSubnetId    = module.subnets["nodes"].id
    secondaryVnicSubnetId  = module.subnets["kpo_pods"].id
    preBootstrapInitScript = filebase64("${path.module}/gitops/c/kpo/pre-bootstrap-init.sh")
    shapeConfigOcpus       = 4
    shapeConfigMemoryInGbs = 16
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
