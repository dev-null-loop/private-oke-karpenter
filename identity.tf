locals {
  karpenter_iam_enabled          = local.karpenter_enabled && var.karpenter.iam.enabled
  bastion_kubeconfig_iam_enabled = local.karpenter_enabled && var.karpenter.install_via_bastion && var.karpenter.bastion_kubeconfig_iam.enabled
  karpenter_service_account      = coalesce(var.karpenter.iam.service_account, var.karpenter.gitops.chart_app, var.karpenter.release_name)

  karpenter_policy_compartment = coalesce(
    var.karpenter.iam.policy_compartment,
    var.karpenter.cluster_compartment
  )

  dynamic_groups = merge(
    local.karpenter_iam_enabled ? {
      karpenter_nodes = {
        tenancy_id    = var.tenancy_ocid
        name          = var.karpenter.iam.dynamic_group
        description   = "Dynamic group for OCI Karpenter launched nodes"
        matching_rule = "ALL {instance.compartment.id = '${var.compartment_ids[coalesce(var.karpenter.iam.node_compartment, var.karpenter.cluster_compartment)]}'}"
      }
    } : {},
    local.bastion_kubeconfig_iam_enabled ? {
      bastion_kubeconfig = {
        tenancy_id  = var.tenancy_ocid
        name        = var.karpenter.bastion_kubeconfig_iam.dynamic_group
        description = "Dynamic group for bastion instance-principal kubeconfig access"
        matching_rule = coalesce(
          var.karpenter.bastion_kubeconfig_iam.matching_rule,
          "ALL {instance.compartment.id = '${var.compartment_ids[coalesce(var.karpenter.bastion_kubeconfig_iam.bastion_compartment, var.instances[var.karpenter.bastion_instance].compartment, var.karpenter.cluster_compartment)]}'}"
        )
      }
    } : {}
  )

  policies = merge(
    local.karpenter_iam_enabled ? {
      karpenter = {
        compartment_id = var.compartment_ids[local.karpenter_policy_compartment]
        name           = var.karpenter.iam.controller_policy
        description    = "OCI Karpenter controller workload identity policy"
        statements = concat(
          [
            "Allow any-user to manage instance-family in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }",
            "Allow any-user to manage volumes in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }",
            "Allow any-user to manage volume-attachments in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }",
            "Allow any-user to manage virtual-network-family in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }",
            "Allow any-user to inspect compartments in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }",
            "Allow dynamic-group ${var.karpenter.iam.dynamic_group} to {CLUSTER_JOIN} in compartment ${local.karpenter_policy_compartment}"
          ],
          var.karpenter.iam.enable_capacity_reservation ? [
            "Allow any-user to use compute-capacity-reservations in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }"
          ] : [],
          var.karpenter.iam.enable_compute_cluster ? [
            "Allow any-user to use compute-clusters in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }"
          ] : [],
          var.karpenter.iam.enable_cluster_pg ? [
            "Allow any-user to use cluster-placement-groups in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }"
          ] : [],
          var.karpenter.iam.enable_defined_tags ? [
            "Allow any-user to use tag-namespaces in compartment ${local.karpenter_policy_compartment} where all { request.principal.type = 'workload', request.principal.namespace = '${var.karpenter.namespace}', request.principal.service_account = '${local.karpenter_service_account}', request.principal.cluster_id = '${module.clusters[var.karpenter.cluster].id}' }"
          ] : []
        )
      }
    } : {},
    local.bastion_kubeconfig_iam_enabled ? {
      bastion_kubeconfig = {
        compartment_id = var.tenancy_ocid
        name           = var.karpenter.bastion_kubeconfig_iam.policy
        description    = "Policy for bastion instance-principal kubeconfig access"
        statements = [
          format(
            "Allow dynamic-group %s to %s in tenancy",
            var.karpenter.bastion_kubeconfig_iam.dynamic_group,
            var.karpenter.bastion_kubeconfig_iam.manage_cluster_family ? "manage cluster-family" : "use clusters"
          )
        ]
      }
    } : {}
  )
}

module "dynamic_groups" {
  source        = "git@github.com:dev-null-loop/oci_identity//dynamic_group"
  for_each      = local.dynamic_groups
  tenancy_id    = each.value.tenancy_id
  name          = each.value.name
  description   = each.value.description
  matching_rule = each.value.matching_rule
  providers     = { oci = oci.home }
}

module "policies" {
  source         = "git@github.com:dev-null-loop/oci_identity//policy"
  for_each       = local.policies
  compartment_id = each.value.compartment_id
  name           = each.value.name
  description    = each.value.description
  statements     = each.value.statements
  providers      = { oci = oci.home }
}
