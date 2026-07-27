locals {
  karpenter_iam_enabled          = local.karpenter_enabled && try(var.karpenter.iam.enabled, true)
  bastion_kubeconfig_iam_enabled = local.karpenter_enabled && try(var.karpenter.install_via_bastion, true) && try(var.karpenter.bastion_kubeconfig_iam.enabled, true)

  karpenter_policy_compartment_name = coalesce(
    try(var.karpenter.iam.policy_compartment_name, null),
    var.karpenter.cluster_compartment_name
  )

  bastion_kubeconfig_compartment_name = coalesce(
    try(var.karpenter.bastion_kubeconfig_iam.bastion_compartment_name, null),
    try(var.instances[var.karpenter.bastion_instance_name].compartment_name, null),
    var.karpenter.cluster_compartment_name
  )

  karpenter_node_compartment_name = coalesce(
    try(var.karpenter.iam.node_compartment_name, null),
    var.karpenter.cluster_compartment_name
  )

  karpenter_policy_compartment_id       = try(var.compartment_ids[local.karpenter_policy_compartment_name], null)
  karpenter_node_compartment_id         = try(var.compartment_ids[local.karpenter_node_compartment_name], null)
  bastion_kubeconfig_compartment_id     = try(var.compartment_ids[local.bastion_kubeconfig_compartment_name], null)
  karpenter_service_account             = try(var.karpenter.iam.service_account, "karpenter")
  karpenter_dynamic_group_name          = try(var.karpenter.iam.dynamic_group_name, "kpo_nodes")
  bastion_kubeconfig_dynamic_group_name = try(var.karpenter.bastion_kubeconfig_iam.dynamic_group_name, "kubeconfig_bastion")
  bastion_kubeconfig_policy_name        = try(var.karpenter.bastion_kubeconfig_iam.policy_name, "kubeconfig_bastion_cluster")
  bastion_kubeconfig_matching_rule = coalesce(
    try(var.karpenter.bastion_kubeconfig_iam.matching_rule, null),
    local.bastion_kubeconfig_compartment_id != null ? "ALL {instance.compartment.id = '${local.bastion_kubeconfig_compartment_id}'}" : null
  )

  karpenter_controller_policy_statements = concat(
    [
      "Allow any-user to manage instance-family in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }",
      "Allow any-user to manage volumes in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }",
      "Allow any-user to manage volume-attachments in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }",
      "Allow any-user to manage virtual-network-family in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }",
      "Allow any-user to inspect compartments in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }"
    ],
    try(var.karpenter.iam.enable_capacity_reservation, false) ? [
      "Allow any-user to use compute-capacity-reservations in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }"
    ] : [],
    try(var.karpenter.iam.enable_compute_cluster, false) ? [
      "Allow any-user to use compute-clusters in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }"
    ] : [],
    try(var.karpenter.iam.enable_cluster_pg, false) ? [
      "Allow any-user to use cluster-placement-groups in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }"
    ] : [],
    try(var.karpenter.iam.enable_defined_tags, false) ? [
      "Allow any-user to use tag-namespaces in compartment ${local.karpenter_policy_compartment_name} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster_name].id}' }"
    ] : []
  )

  bastion_kubeconfig_policy_statements = [
    format(
      "Allow dynamic-group %s to %s in compartment %s",
      local.bastion_kubeconfig_dynamic_group_name,
      try(var.karpenter.bastion_kubeconfig_iam.manage_cluster_family, true) ? "manage cluster-family" : "use clusters",
      var.karpenter.cluster_compartment_name
    )
  ]
}

module "karpenter_node_dynamic_group" {
  count         = local.karpenter_iam_enabled ? 1 : 0
  source        = "../oci_identity/dynamic_group"
  tenancy_id    = var.tenancy_ocid
  name          = local.karpenter_dynamic_group_name
  description   = "Dynamic group for OCI Karpenter launched nodes"
  matching_rule = "ALL {instance.compartment.id = '${local.karpenter_node_compartment_id}'}"
  providers     = { oci = oci.home }
}

module "karpenter_controller_policy" {
  count          = local.karpenter_iam_enabled ? 1 : 0
  source         = "../oci_identity/policy"
  compartment_id = local.karpenter_policy_compartment_id
  name           = try(var.karpenter.iam.controller_policy_name, "kpo_controller")
  description    = "OCI Karpenter controller workload identity policy"
  statements     = local.karpenter_controller_policy_statements
  providers      = { oci = oci.home }
}

module "karpenter_cluster_join_policy" {
  count          = local.karpenter_iam_enabled ? 1 : 0
  source         = "../oci_identity/policy"
  compartment_id = local.karpenter_policy_compartment_id
  name           = try(var.karpenter.iam.cluster_join_policy_name, "kpo_cluster_join")
  description    = "OCI Karpenter node CLUSTER_JOIN policy"
  statements = [
    "Allow dynamic-group ${local.karpenter_dynamic_group_name} to {CLUSTER_JOIN} in compartment ${local.karpenter_policy_compartment_name}"
  ]
  providers = { oci = oci.home }
}

module "bastion_kubeconfig_dynamic_group" {
  count         = local.bastion_kubeconfig_iam_enabled ? 1 : 0
  source        = "../oci_identity/dynamic_group"
  tenancy_id    = var.tenancy_ocid
  name          = local.bastion_kubeconfig_dynamic_group_name
  description   = "Dynamic group for bastion instance-principal kubeconfig access"
  matching_rule = local.bastion_kubeconfig_matching_rule
  providers     = { oci = oci.home }
}

module "bastion_kubeconfig_policy" {
  count          = local.bastion_kubeconfig_iam_enabled ? 1 : 0
  source         = "../oci_identity/policy"
  compartment_id = local.karpenter_policy_compartment_id
  name           = local.bastion_kubeconfig_policy_name
  description    = "Policy for bastion instance-principal kubeconfig access"
  statements     = local.bastion_kubeconfig_policy_statements
  providers      = { oci = oci.home }
}
