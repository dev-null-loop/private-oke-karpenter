locals {
  network_entity_ids = merge(
    { for k, v in module.internet_gateways : "ig_${k}" => v.id },
    { for k, v in module.nat_gateways : "ng_${k}" => v.id },
    { for k, v in module.service_gateways : "sg_${k}" => v.id }
  )

  services = {
    for svc in data.oci_core_services.svcs.services :
    (startswith(lower(svc.cidr_block), "all-") ? "services" : "objectstorage") => {
      cidr_block = svc.cidr_block
      id         = svc.id
    }
  }

  availability_domains = {
    for idx, ad in data.oci_identity_availability_domains.ads.availability_domains : idx + 1 => ad.name
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

  instances = {
    for k, v in var.instances : k => merge(v, {
      availability_domain = local.availability_domains[v.availability_domain]
      create_vnic_details = merge(v.create_vnic_details, {
        subnet_id = try(module.subnets[v.create_vnic_details.subnet_name].id, v.create_vnic_details.subnet_id)
      })
      metadata = merge(
        {
          ssh_authorized_keys = join("\n", v.ssh_public_keys)
        },
        length(v.cloud_init) == 0 ? {} : {
          user_data = base64encode(
            v.cloud_init[0].content != null ? v.cloud_init[0].content : file(v.cloud_init[0].filename)
          )
        }
      )
      source_details = merge(v.source_details, {
        source_id = var.source_ids[v.source_details.source_name]
      })
    })
  }

  clusters = {
    for k, v in var.clusters : k => merge(v, {
      endpoint_config = v.endpoint_config != null ? merge(v.endpoint_config, {
        subnet_id = module.subnets[v.endpoint_config.subnet_name].id
      }) : null
      options = v.options != null ? merge(v.options, {
        service_lb_subnet_ids = [for name in v.options.service_lb_subnet_names : module.subnets[name].id]
      }) : null
    })
  }

  node_pools = {
    for k, v in var.node_pools : k => merge(v, {
      image_id = var.oke_worker_node_image_ids[v.node_source_details.image_name]
      node_config_details = merge(v.node_config_details, {
        placement_configs = [
          for pc in v.node_config_details.placement_configs : {
            availability_domain     = local.availability_domains[pc.availability_domain]
            fault_domains           = [for fd in pc.fault_domains : "FAULT-DOMAIN-${fd}"]
            subnet_id               = module.subnets[pc.subnet_name].id
            capacity_reservation_id = pc.capacity_reservation_id
          }
        ]
        node_pool_pod_network_option_details = v.node_config_details.node_pool_pod_network_option_details != null ? merge(v.node_config_details.node_pool_pod_network_option_details, {
          pod_subnet_ids = [
            for name in v.node_config_details.node_pool_pod_network_option_details.pod_subnet_names :
            module.subnets[name].id
          ]
        }) : null
      })
    })
  }
}
