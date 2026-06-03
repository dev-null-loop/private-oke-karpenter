data "oci_core_services" "these" {}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  network_entity_ids = merge(
    { for k, v in module.ig : "ig_${k}" => v.id },
    { for k, v in module.ng : "ng_${k}" => v.id },
    { for k, v in module.sg : "sg_${k}" => v.id }
  )

  services = {
    for svc in data.oci_core_services.these.services :
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
        subnet_id = try(module.sn[v.create_vnic_details.subnet_name].id, v.create_vnic_details.subnet_id)
      })
      source_details = merge(v.source_details, {
        source_id = var.source_ids[v.source_details.source_name]
      })
      ssh_public_keys = join("\n", v.ssh_public_keys)
      cloud_init = [
        for part in v.cloud_init : merge(part, {
          content = try(part.content, null)
          vars = merge(
            try(part.vars, {}),
            {
              filename                       = try(part.vars.filename, null)
              kubeconfig_content             = try(module.kubeconfig[v.managed_cluster].kubeconfig_instance_principal, null)
              subnet_id                      = try(module.clusters[v.managed_cluster].service_lb_subnet_ids[0], null)
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
        })
      ]
    })
  }

  clusters = {
    for k, v in var.clusters : k => merge(v, {
      endpoint_config = merge(v.endpoint_config, {
        subnet_id = module.sn[v.endpoint_config.subnet_name].id
      })
      options = v.options != null ? merge(v.options, {
        service_lb_subnet_ids = [for name in try(v.options.service_lb_subnet_names, []) : module.sn[name].id]
      }) : null
    })
  }

  node_pools = {
    for k, v in var.node_pools : k => merge(v, {
      image_id       = var.oke_worker_node_image_ids[v.node_source_details.image_name]
      subnet_ids     = { for name, subnet in module.sn : name => subnet.id }
      pod_subnet_ids = { for name, subnet in module.sn : name => subnet.id }
    })
  }
}
