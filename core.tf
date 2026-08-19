module "vcns" {
  source                 = "git@github.com:dev-null-loop/oci_core//vcn"
  for_each               = var.vcns
  compartment_id         = var.compartment_ids[each.value.compartment]
  cidr_blocks            = each.value.cidr_blocks
  dns_label              = each.value.dns_label
  display_name           = each.value.display_name
  is_ipv6enabled         = each.value.is_ipv6enabled
  lookup_dns_resolver_id = false
}

module "internet_gateways" {
  source         = "git@github.com:dev-null-loop/oci_core//internet_gateway"
  for_each       = var.internet_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn].compartment_id
  vcn_id         = module.vcns[each.value.vcn].id
}

module "nat_gateways" {
  source         = "git@github.com:dev-null-loop/oci_core//nat_gateway"
  for_each       = var.nat_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn].compartment_id
  vcn_id         = module.vcns[each.value.vcn].id
}

module "service_gateways" {
  source         = "git@github.com:dev-null-loop/oci_core//service_gateway"
  for_each       = var.service_gateways
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn].compartment_id
  service_id     = local.services["services"].id
  vcn_id         = module.vcns[each.value.vcn].id
}

module "security_lists" {
  source         = "git@github.com:dev-null-loop/oci_core//security_list"
  for_each       = local.security_lists
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn].compartment_id
  vcn_id         = module.vcns[each.value.vcn].id
  egress_rules   = each.value.egress_rules
  ingress_rules  = each.value.ingress_rules
}

module "route_tables" {
  source         = "git@github.com:dev-null-loop/oci_core//route_table"
  for_each       = local.route_tables
  display_name   = each.value.display_name
  compartment_id = module.vcns[each.value.vcn].compartment_id
  vcn_id         = module.vcns[each.value.vcn].id
  route_rules    = each.value.route_rules
}

module "subnets" {
  source                     = "git@github.com:dev-null-loop/oci_core//subnet"
  for_each                   = var.subnets
  compartment_id             = var.compartment_ids[each.value.compartment]
  display_name               = each.value.display_name
  cidr_block                 = each.value.cidr_block
  vcn_id                     = module.vcns[each.value.vcn].id
  dns_label                  = each.value.dns_label
  prohibit_internet_ingress  = each.value.prohibit_internet_ingress
  prohibit_public_ip_on_vnic = each.value.prohibit_public_ip_on_vnic
  route_table_id             = each.value.route_table == null ? null : module.route_tables[each.value.route_table].id
  security_list_ids          = length(each.value.security_lists) == 0 ? null : [for name in each.value.security_lists : module.security_lists[name].id]
}

module "instances" {
  source                     = "git@github.com:dev-null-loop/oci_core//instance"
  for_each                   = local.instances
  availability_domain        = each.value.availability_domain
  compartment_id             = var.compartment_ids[each.value.compartment]
  enable_vnic_lookup_outputs = false
  create_vnic_details        = each.value.create_vnic_details
  display_name               = each.value.display_name
  metadata                   = each.value.metadata
  shape                      = each.value.shape
  shape_config               = each.value.shape_config
  source_details             = each.value.source_details
}
