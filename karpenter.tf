locals {
  karpenter_apiserver_endpoint = coalesce(
    module.clusters[var.karpenter.cluster].endpoints[0].private_endpoint,
    module.clusters[var.karpenter.cluster].endpoints[0].kubernetes
  )
  karpenter_ssh_authorized_keys = (
    length(var.karpenter.ocinodeclass.ssh_authorized_keys) > 0 ?
    var.karpenter.ocinodeclass.ssh_authorized_keys :
    try(var.instances[var.karpenter.bastion_instance].ssh_public_keys, [])
  )
  karpenter_primary_subnet_id = module.subnets[var.karpenter.ocinodeclass.primary_subnet].id
  karpenter_pod_subnet_ids    = [for name in var.karpenter.ocinodeclass.pod_subnets : module.subnets[name].id]
  karpenter_ocinodeclass_secondary_vnic_configs = var.karpenter.ocinodeclass.secondary_vnic_ip_count != null ? [
    for sid in(var.karpenter.ocinodeclass.use_same_node_and_pod_subnet ? [local.karpenter_primary_subnet_id] : local.karpenter_pod_subnet_ids) : {
      subnet_id              = sid
      ip_count               = var.karpenter.ocinodeclass.secondary_vnic_ip_count
      assign_public_ip       = var.karpenter.ocinodeclass.secondary_vnic_config.assign_public_ip
      skip_source_dest_check = var.karpenter.ocinodeclass.secondary_vnic_config.skip_source_dest_check
    }
  ] : []
}

module "karpenter" {
  source = "./addons/karpenter"
  karpenter = merge(var.karpenter, {
    cluster_compartment_id = var.compartment_ids[var.karpenter.cluster_compartment]
    vcn_compartment_id     = var.compartment_ids[var.karpenter.vcn_compartment]
    apiserver_endpoint     = local.karpenter_apiserver_endpoint
    ocinodeclass = merge(var.karpenter.ocinodeclass, {
      ssh_authorized_keys    = local.karpenter_ssh_authorized_keys
      primary_subnet_id      = local.karpenter_primary_subnet_id
      secondary_vnic_configs = local.karpenter_ocinodeclass_secondary_vnic_configs
    })
  })
}

output "karpenter" {
  sensitive = true
  value = local.karpenter_enabled ? {
    values_file             = module.karpenter.values_file
    ocinodeclass_file       = module.karpenter.ocinodeclass_file
    nodepool_file           = module.karpenter.nodepool_file
    test_workload_file      = module.karpenter.test_workload_file
    collect_debug_file      = module.karpenter.collect_debug_file
    bastion_public_ip       = try(module.instances[var.karpenter.bastion_instance].public_ip, null)
    kubeconfig_ip_principal = try(module.kubeconfigs[var.karpenter.cluster].kubeconfig_instance_principal, null)
    apiserver_endpoint      = local.karpenter_apiserver_endpoint
    install_command = (
      try(module.instances[var.karpenter.bastion_instance].public_ip, null) != null ?
      "ssh opc@${module.instances[var.karpenter.bastion_instance].public_ip}" :
      null
    )
  } : null
}
