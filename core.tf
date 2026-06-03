module "vcns" {
  source                 = "git@github.com:dev-null-loop/oci_core//vcn"
  for_each               = var.vcns
  compartment_id         = var.compartment_ids[each.value.compartment_name]
  cidr_blocks            = each.value.cidr_blocks
  dns_label              = each.value.dns_label
  display_name           = each.value.display_name
  is_ipv6enabled         = each.value.is_ipv6enabled
  lookup_dns_resolver_id = false
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
  service_id     = local.services[each.value.service_name].id
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
  route_table_id             = each.value.route_table_name == null ? null : module.rt[each.value.route_table_name].id
  security_list_ids          = length(each.value.security_list_names) == 0 ? null : [for name in each.value.security_list_names : module.sl[name].id]
}

module "vm" {
  source                     = "git@github.com:dev-null-loop/oci_core//instance"
  for_each                   = local.instances
  availability_domain        = each.value.availability_domain
  compartment_id             = var.compartment_ids[each.value.compartment_name]
  enable_vnic_lookup_outputs = false
  create_vnic_details        = each.value.create_vnic_details
  display_name               = each.value.display_name
  fault_domain               = each.value.fault_domain
  preserve_boot_volume       = each.value.preserve_boot_volume
  ssh_public_keys            = each.value.ssh_public_keys
  shape                      = each.value.shape
  shape_config               = each.value.shape_config
  source_details             = each.value.source_details
  cloud_init                 = each.value.cloud_init
  state                      = each.value.state
  depends_on = [
    module.karpenter_controller_policy,
    module.karpenter_cluster_join_policy,
  ]
}
