module "vcns" {
  source         = "git@github.com:dev-null-loop/oci_core//vcn"
  for_each       = var.vcns
  compartment_id = var.compartment_ids[each.value.compartment_name]
  cidr_blocks    = each.value.cidr_blocks
  dns_label      = each.value.dns_label
  display_name   = each.value.display_name
  is_ipv6enabled = each.value.is_ipv6enabled
}

module "ig" {
  source         = "git@github.com:dev-null-loop/oci_core//internet_gateway"
  for_each       = var.internet_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn_name].compartment_id
  vcn_id         = module.vcns[each.value.vcn_name].id
}

module "ng" {
  source         = "git@github.com:dev-null-loop/oci_core//nat_gateway"
  for_each       = var.nat_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn_name].compartment_id
  vcn_id         = module.vcns[each.value.vcn_name].id
}

module "sg" {
  source         = "git@github.com:dev-null-loop/oci_core//service_gateway"
  for_each       = var.service_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn_name].compartment_id
  service_id     = local.services[try(each.value.service_name, "services")].id
  vcn_id         = module.vcns[each.value.vcn_name].id
}

module "sl" {
  source         = "git@github.com:dev-null-loop/oci_core//security_list"
  for_each       = local.security_lists
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn_name].compartment_id
  vcn_id         = module.vcns[each.value.vcn_name].id
  egress_rules   = each.value.egress_rules
  ingress_rules  = each.value.ingress_rules
}

module "rt" {
  source         = "git@github.com:dev-null-loop/oci_core//route_table"
  for_each       = local.route_tables
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn_name].compartment_id
  vcn_id         = module.vcns[each.value.vcn_name].id
  route_rules    = each.value.route_rules
}

module "sn" {
  source                     = "git@github.com:dev-null-loop/oci_core//subnet"
  for_each                   = var.subnets
  compartment_id             = var.compartment_ids[each.value.compartment_name]
  display_name               = each.value.display_name
  cidr_block                 = each.value.cidr_block
  vcn_id                     = module.vcns[each.value.vcn_name].id
  dns_label                  = each.value.dns_label
  prohibit_internet_ingress  = each.value.prohibit_internet_ingress
  prohibit_public_ip_on_vnic = each.value.prohibit_public_ip_on_vnic
  route_table_id             = module.rt[each.value.rt_name].id
  security_list_ids          = [module.sl[each.value.sl_name].id]
}

module "vm" {
  source                     = "git@github.com:dev-null-loop/oci_core//instance"
  for_each                   = var.instances
  availability_domain        = each.value.availability_domain
  compartment_id             = var.compartment_ids[each.value.compartment_name]
  agent_config               = each.value.agent_config
  enable_vnic_lookup_outputs = false
  create_vnic_details = {
    assign_public_ip       = each.value.create_vnic_details.assign_public_ip
    defined_tags           = each.value.create_vnic_details.defined_tags
    display_name           = each.value.create_vnic_details.display_name
    freeform_tags          = each.value.create_vnic_details.freeform_tags
    hostname_label         = each.value.create_vnic_details.hostname_label
    private_ip             = each.value.create_vnic_details.private_ip
    skip_source_dest_check = each.value.create_vnic_details.skip_source_dest_check
    subnet_id              = module.sn[each.value.create_vnic_details.subnet_name].id
  }
  display_name    = each.value.display_name
  ssh_public_keys = join("\n", [for key in each.value.ssh_public_keys : key])
  shape           = each.value.shape
  shape_config    = each.value.shape_config
  source_details = {
    source_id = var.source_ids[each.value.source_details.source_name]
  }
  cloud_init = [
    for v in each.value.cloud_init : {
      content_type = v.content_type
      filename     = v.filename
      content      = try(v.content, null)
      vars = merge(
	try(v.vars, {}),
	{
	  filename                       = try(v.vars.filename, null)
	  kubeconfig_content             = try(module.kubeconfig[each.value.managed_cluster].kubeconfig_instance_principal, null)
	  subnet_id                      = try(module.clusters[each.value.managed_cluster].service_lb_subnet_ids[0], null)
	  cluster_compartment_id         = try(local.karpenter_cluster_compartment_id, null)
	  vcn_compartment_id             = try(local.karpenter_vcn_compartment_id, null)
	  apiserver_endpoint             = try(local.karpenter_apiserver_endpoint, null)
	  oci_vcn_ip_native              = try(var.karpenter.oci_vcn_ip_native, null)
	  ip_families_yaml               = try(yamlencode(var.karpenter.ip_families), null)
	  karpenter_namespace            = try(var.karpenter.namespace, null)
	  karpenter_chart_version        = try(var.karpenter.chart_version, null)
	  karpenter_release_name         = try(var.karpenter.release_name, null)
	  karpenter_values_content       = try(local.karpenter_values_content, null)
	  karpenter_ocinodeclass_content = try(local.karpenter_ocinodeclass_content, null)
	  karpenter_nodepool_content     = try(local.karpenter_nodepool_content, null)
	  karpenter_repro_content        = try(local.karpenter_repro_workload_content, null)
	}
      )
    }
  ]
  depends_on = [
    module.karpenter_controller_policy,
    module.karpenter_cluster_join_policy,
  ]
}
