data "oci_core_services" "this" {}

locals {
  network_entity_ids = merge(
    { for k, v in module.ig : "ig_${k}" => v.id },
    { for k, v in module.ng : "ng_${k}" => v.id },
    { for k, v in module.sg : "sg_${k}" => v.id }
  )

  services = {
    for svc in data.oci_core_services.this.services :
    (startswith(lower(svc.cidr_block), "all-") ? "services" : "objectstorage") => {
      cidr_block = svc.cidr_block
      id         = svc.id
    }
  }

  security_lists = {
    for k, v in var.security_lists : k => merge(v, {
      egress_rules = [
	for rule in v.egress_rules : merge(rule, {
	  destination = try(local.services[rule.destination].cidr_block, rule.destination)
	})
      ]
    })
  }

  route_tables = {
    for k, v in var.route_tables : k => merge(v, {
      route_rules = [
	for rr in v.route_rules : {
	  description       = rr.description
	  destination       = try(local.services[rr.destination].cidr_block, rr.destination)
	  destination_type  = rr.destination_type
	  network_entity_id = local.network_entity_ids[rr.network_entity_name]
	}
      ]
    })
  }
}
