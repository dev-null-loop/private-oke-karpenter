locals {
  karpenter_enabled            = var.karpenter.enabled
  karpenter_apiserver_endpoint = coalesce(module.clusters[var.karpenter.cluster].endpoints[0].private_endpoint, module.clusters[var.karpenter.cluster].endpoints[0].kubernetes)
  karpenter_primary_subnet_id  = module.subnets[var.karpenter.ocinodeclass.primary_subnet].id
  karpenter_pod_subnet_ids     = [for name in var.karpenter.ocinodeclass.pod_subnets : module.subnets[name].id]
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
  source                 = "./addons/karpenter"
  enabled                = local.karpenter_enabled
  namespace              = var.karpenter.namespace
  chart_version          = var.karpenter.chart_version
  release_name           = var.karpenter.release_name
  gitops                 = {
    repo_url         = var.karpenter.gitops.repo_url
    revision         = var.karpenter.gitops.revision
    argocd_namespace = var.karpenter.gitops.argocd_namespace
    chart_app        = var.karpenter.gitops.chart_app
    manifests_app    = var.karpenter.gitops.manifests_app
  }
  cluster_compartment_id = var.compartment_ids[var.karpenter.cluster_compartment]
  vcn_compartment_id     = var.compartment_ids[var.karpenter.vcn_compartment]
  apiserver_endpoint     = local.karpenter_apiserver_endpoint
  oci_vcn_ip_native      = var.karpenter.oci_vcn_ip_native
  ip_families            = var.karpenter.ip_families
  ocinodeclass = merge(var.karpenter.ocinodeclass, {
    primary_subnet_id      = local.karpenter_primary_subnet_id
    secondary_vnic_configs = local.karpenter_ocinodeclass_secondary_vnic_configs
  })
  nodepool      = var.karpenter.nodepool
  test_workload = var.karpenter.test_workload
}

output "karpenter" {
  sensitive = true
  value = local.karpenter_enabled ? {
    values_file             = module.karpenter.values_file
    ocinodeclass_file       = module.karpenter.ocinodeclass_file
    nodepool_file           = module.karpenter.nodepool_file
    test_workload_file      = module.karpenter.test_workload_file
    collect_debug_file      = module.karpenter.collect_debug_file
    gitops_chart_app_file   = module.karpenter.gitops_chart_application_file
    gitops_manifests_file   = module.karpenter.gitops_manifests_application_file
    bastion_public_ip       = contains(keys(module.instances), var.karpenter.bastion_instance) ? module.instances[var.karpenter.bastion_instance].public_ip : null
    kubeconfig_ip_principal = contains(keys(module.kubeconfigs), var.karpenter.cluster) ? module.kubeconfigs[var.karpenter.cluster].kubeconfig_instance_principal : null
    apiserver_endpoint      = local.karpenter_apiserver_endpoint
    install_command         = contains(keys(module.instances), var.karpenter.bastion_instance) ? "ssh opc@${module.instances[var.karpenter.bastion_instance].public_ip}" : null
  } : null
}
