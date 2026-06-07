module "clusters" {
  source             = "git@github.com:dev-null-loop/oci_containerengine//cluster"
  for_each           = local.clusters
  compartment_id     = var.compartment_ids[each.value.compartment_name]
  name               = each.value.name
  kubernetes_version = each.value.kubernetes_version
  vcn_id             = module.vcns[each.value.vcn_name].id
  cluster_pod_network_options = {
    cni_type = each.value.cni_type
  }
  endpoint_config = each.value.endpoint_config
  options         = each.value.options
}

module "node_pools" {
  source                           = "git@github.com:dev-null-loop/oci_containerengine//node_pool"
  for_each                         = local.node_pools
  cluster_id                       = module.clusters[each.value.cluster_name].id
  compartment_id                   = var.compartment_ids[each.value.compartment_name]
  kubernetes_version               = each.value.kubernetes_version
  name                             = each.value.name
  node_source_details              = each.value.node_source_details
  image_id                         = each.value.image_id
  cloud_init                       = each.value.cloud_init
  node_config_details              = each.value.node_config_details
  node_eviction_node_pool_settings = each.value.node_eviction_node_pool_settings
  node_shape                       = each.value.node_shape
  node_shape_config                = each.value.node_shape_config
  ssh_public_key                   = each.value.ssh_public_key
  subnet_ids                       = each.value.subnet_ids
  pod_subnet_ids                   = each.value.pod_subnet_ids
}

module "kubeconfig" {
  source     = "git@github.com:dev-null-loop/oci_containerengine//kubeconfig"
  for_each   = var.clusters
  cluster_id = module.clusters[each.key].id
}

# module "addons" {
#   source     = "git@github.com:dev-null-loop/oci_containerengine//addon"
#   for_each   = var.addons
#   cluster_id = module.clusters[each.value.cluster_name].id
#   addon_name = each.value.addon_name
#   configurations = (
#     each.value.addon_name == "NativeIngressController" ?
#     merge(each.value.configurations,
#       {
#	compartmentId        = var.compartment_ids[each.value.compartment_name],
#	loadBalancerSubnetId = module.subnets[each.value.load_balancer_subnet_name].id
#       }
#     ) :
#     each.value.addon_name == "ClusterAutoscaler" ?
#     merge(each.value.configurations,
#       {
#	nodes                  = "${each.value.min_nodes}:${each.value.max_nodes}:${module.node_pools[each.value.node_pool_name].id}",
#	nodeGroupAutoDiscovery = "compartmentId:${var.compartment_ids[each.value.compartment_name]},nodepoolTags:${join(",", [for k, v in each.value.node_pool_tags : "${k}=${v}"])},min:${each.value.min_nodes},max:${each.value.max_nodes}"
#       }
#     ) :
#     each.value.configurations
#   )
# }
