output "sshuttle" {
  value = [for k, v in var.instances :
    (
      try(module.instances[k].public_ip, null) != null ?
      "sshuttle -x ${module.instances[k].public_ip} --dns -NHr opc@${module.instances[k].public_ip} ${module.vcns[var.subnets[v.create_vnic_details.subnet].vcn].cidr_blocks[0]}" :
      "sshuttle pending for ${k}: public_ip not assigned yet"
    )
  ]
}

output "vcns" {
  value = { for k, v in module.vcns :
    k => {
      display_name = v.display_name
      cidr_blocks  = v.cidr_blocks
      subnets = [for i, j in module.subnets :
        {
          name       = i
          cidr_block = j.cidr_block
        } if j.vcn_id == v.id
      ]
    }
  }
}

output "instances" {
  value = { for k, v in module.instances :
    k => {
      public_ip  = v.public_ip == "" ? null : v.public_ip
      private_ip = v.private_ip
    }
  }
}

output "clusters" {
  value = { for k, v in module.clusters :
    k => {
      endpoints                 = v.endpoints
      kubernetes_network_config = v.kubernetes_network_config
      service_lb_subnet_ids     = v.service_lb_subnet_ids
      worker_nodes = zipmap(keys(module.node_pools),
        [for v in values(module.node_pools) :
          [for node in v.nodes : node.private_ip]
      ])
    }
  }
}

output "gitops_kpo_patch_values" {
  value = {
    values_yaml = {
      clusterCompartmentId    = var.compartment_ids[var.karpenter.cluster_compartment]
      vcnCompartmentId        = var.compartment_ids[var.subnets["nodes"].compartment]
      apiserverEndpoint       = split(":", coalesce(module.clusters[var.karpenter.cluster].endpoints[0].private_endpoint, module.clusters[var.karpenter.cluster].endpoints[0].kubernetes))[0]
    }
    ocinodeclass_yaml = {
      primaryVnicSubnetId    = module.subnets["nodes"].id
      secondaryVnicSubnetId  = module.subnets["kpo_pods"].id
    }
  }
}
