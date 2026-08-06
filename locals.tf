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

  instance_template_vars = {
    for k, v in var.instances : k => merge(
      concat(
        [for part in v.cloud_init : part.vars != null ? part.vars : {}],
        [{
        kubeconfig_content       = contains(keys(var.clusters), v.managed_cluster) ? module.kubeconfigs[v.managed_cluster].kubeconfig_instance_principal : ""
        chart_version            = local.karpenter_enabled ? var.karpenter.chart_version : ""
        namespace                = local.karpenter_enabled ? var.karpenter.namespace : "karpenter"
        release_name             = local.karpenter_enabled ? var.karpenter.release_name : "karpenter"
        values_content           = local.karpenter_enabled && module.karpenter.values_content != null ? module.karpenter.values_content : ""
        ocinodeclass_content     = local.karpenter_enabled && module.karpenter.ocinodeclass_content != null ? module.karpenter.ocinodeclass_content : ""
        nodepool_content         = local.karpenter_enabled && module.karpenter.nodepool_content != null ? module.karpenter.nodepool_content : ""
        test_workload_content    = local.karpenter_enabled && module.karpenter.test_workload_content != null ? module.karpenter.test_workload_content : ""
        argocd_namespace         = local.karpenter_enabled ? var.karpenter.gitops.argocd_namespace : "argocd"
        argocd_release_name      = local.karpenter_enabled ? var.karpenter.gitops.argocd_release_name : "argocd"
        argocd_chart_version     = local.karpenter_enabled ? var.karpenter.gitops.argocd_chart_version : "8.4.0"
        gitops_repo_url          = local.karpenter_enabled ? var.karpenter.gitops.repo_url : ""
        gitops_revision          = local.karpenter_enabled ? var.karpenter.gitops.revision : "main"
        gitops_root_app          = local.karpenter_enabled ? var.karpenter.gitops.root_app : "root"
        gitops_repository_secret = local.karpenter_enabled ? var.karpenter.gitops.repository_secret : ""
      }]
      )...
    )
  }

  instance_cloud_init_parts = {
    for k, v in var.instances : k => v.cloud_init
    if length(v.cloud_init) > 0
  }

  instance_cloud_init_content = {
    for k, v in var.instances : k =>
    length(v.cloud_init) == 0 ? null : data.cloudinit_config.instances[k].rendered
  }

  instances = {
    for k, v in var.instances : k => merge(v, {
      availability_domain = local.availability_domains[v.availability_domain]
      create_vnic_details = merge(v.create_vnic_details, {
        subnet_id = try(module.subnets[v.create_vnic_details.subnet].id, v.create_vnic_details.subnet_id)
      })
      metadata = merge(
        {
          ssh_authorized_keys = join("\n", v.ssh_public_keys)
        },
        length(v.cloud_init) == 0 ? {} : {
          user_data = base64encode(local.instance_cloud_init_content[k])
        }
      )
      source_details = merge(v.source_details, {
        source_id = var.source_ids[v.source_details.source_name]
      })
    })
  }

  clusters = {
    for k, v in var.clusters : k => merge(v, {
      endpoint_config = merge(v.endpoint_config, {
        subnet_id = module.subnets[v.endpoint_config.subnet].id
      })
      options = merge(v.options, {
        service_lb_subnet_ids = [for name in v.options.service_lb_subnets : module.subnets[name].id]
      })
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
            subnet_id               = module.subnets[pc.subnet].id
            capacity_reservation_id = pc.capacity_reservation_id
          }
        ]
        node_pool_pod_network_option_details = merge(v.node_config_details.node_pool_pod_network_option_details, {
          pod_subnet_ids = [
            for name in v.node_config_details.node_pool_pod_network_option_details.pod_subnets :
            module.subnets[name].id
          ]
        })
      })
    })
  }
}

data "cloudinit_config" "instances" {
  for_each      = local.instance_cloud_init_parts
  gzip          = false
  base64_encode = false

  dynamic "part" {
    for_each = each.value
    iterator = part

    content {
      content_type = coalesce(part.value.content_type, "text/x-shellscript")
      filename     = part.value.filename != null ? basename(part.value.filename) : null
      content = (
        part.value.filename != null ?
        templatefile("${path.root}/${part.value.filename}", local.instance_template_vars[each.key]) :
        templatestring(part.value.content, local.instance_template_vars[each.key])
      )
      merge_type = "list(append)+dict(no_replace,recurse_list)+str(append)"
    }
  }
}
