locals {
  karpenter_enabled                = var.karpenter.enabled
  karpenter_cluster_compartment_id = try(var.compartment_ids[var.karpenter.cluster_compartment_name], null)
  karpenter_vcn_compartment_id     = try(var.compartment_ids[var.karpenter.vcn_compartment_name], null)
  karpenter_apiserver_endpoint = try(
    module.clusters[var.karpenter.cluster_name].endpoints[0].private_endpoint,
    module.clusters[var.karpenter.cluster_name].endpoints[0].kubernetes,
    null
  )

  karpenter_primary_subnet_id = try(module.sn[var.karpenter.ocinodeclass.primary_subnet_name].id, null)
  karpenter_pod_subnet_ids = [
    for n in try(var.karpenter.ocinodeclass.pod_subnet_names, []) : module.sn[n].id
  ]

  karpenter_ocinodeclass_secondary_vnic_configs = (
    try(var.karpenter.ocinodeclass.secondary_vnic_ip_count, null) != null ? [
      for sid in(
        try(var.karpenter.ocinodeclass.use_same_node_and_pod_subnet, false) ?
        [local.karpenter_primary_subnet_id] :
        local.karpenter_pod_subnet_ids
        ) : {
        subnet_id = sid
        ip_count  = var.karpenter.ocinodeclass.secondary_vnic_ip_count
      }
    ] : []
  )

  karpenter_values_content = local.karpenter_enabled ? templatefile("${path.module}/karpenter/values.yaml.tftpl", {
    cluster_compartment_id = local.karpenter_cluster_compartment_id
    vcn_compartment_id     = local.karpenter_vcn_compartment_id
    apiserver_endpoint     = local.karpenter_apiserver_endpoint
    oci_vcn_ip_native      = var.karpenter.oci_vcn_ip_native
    ip_families            = var.karpenter.ip_families
  }) : null

  karpenter_ocinodeclass_content = local.karpenter_enabled ? yamlencode({
    apiVersion = "oci.oraclecloud.com/v1beta1"
    kind       = "OCINodeClass"
    metadata = {
      name = var.karpenter.ocinodeclass.name
    }
    spec = merge(
      length(var.karpenter.ocinodeclass.shape_configs) > 0 ? {
        shapeConfigs = [
          for cfg in var.karpenter.ocinodeclass.shape_configs : merge(
            {
              ocpus       = cfg.ocpus
              memoryInGbs = cfg.memory_in_gbs
            },
            try(cfg.baseline_ocpu_utilization, null) != null ? {
              baselineOcpuUtilization = cfg.baseline_ocpu_utilization
            } : {}
          )
        ]
      } : {},
      {
        volumeConfig = {
          bootVolumeConfig = {
            imageConfig = merge(
              {
                imageType = try(var.karpenter.ocinodeclass.image_config.image_type, "OKEImage")
              },
              try(var.karpenter.ocinodeclass.image_config.image_id, null) != null ? {
                imageId = var.karpenter.ocinodeclass.image_config.image_id
              } : {},
              try(var.karpenter.ocinodeclass.image_config.image_id, null) == null ? {
                imageFilter = merge(
                  try(var.karpenter.ocinodeclass.image_config.os_filter, null) != null ? {
                    osFilter = var.karpenter.ocinodeclass.image_config.os_filter
                  } : {},
                  try(var.karpenter.ocinodeclass.image_config.os_version_filter, null) != null ? {
                    osVersionFilter = var.karpenter.ocinodeclass.image_config.os_version_filter
                  } : {}
                )
              } : {}
            )
          }
        }
        networkConfig = merge(
          {
            primaryVnicConfig = {
              subnetConfig = {
                subnetId = local.karpenter_primary_subnet_id
              }
            }
          },
          length(local.karpenter_ocinodeclass_secondary_vnic_configs) > 0 ? {
            secondaryVnicConfigs = [
              for cfg in local.karpenter_ocinodeclass_secondary_vnic_configs : {
                subnetConfig = {
                  subnetId = cfg.subnet_id
                }
                ipCount = cfg.ip_count
              }
            ]
          } : {}
        )
      }
    )
  }) : null

  karpenter_nodepool_content = local.karpenter_enabled ? yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.karpenter.nodepool.name
    }
    spec = {
      template = {
        spec = {
          expireAfter            = var.karpenter.nodepool.expire_after
          terminationGracePeriod = var.karpenter.nodepool.termination_grace_period
          nodeClassRef = {
            group = "oci.oraclecloud.com"
            kind  = "OCINodeClass"
            name  = var.karpenter.ocinodeclass.name
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.karpenter.nodepool.capacity_types
            },
            {
              key      = "oci.oraclecloud.com/instance-shape"
              operator = "In"
              values   = var.karpenter.nodepool.instance_shapes
            }
          ]
        }
      }
      disruption = {
        budgets = [
          {
            nodes = var.karpenter.nodepool.budget_nodes
          }
        ]
        consolidateAfter    = var.karpenter.nodepool.consolidate_after
        consolidationPolicy = var.karpenter.nodepool.consolidation_policy
      }
      limits = merge(
        {
          cpu = var.karpenter.nodepool.cpu_limit
        },
        try(var.karpenter.nodepool.memory_limit, null) != null ? {
          memory = var.karpenter.nodepool.memory_limit
        } : {}
      )
    }
  }) : null

  karpenter_repro_workload_content = local.karpenter_enabled && try(var.karpenter.repro.enabled, false) ? yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name = "issue-25-burst"
    }
    spec = {
      replicas = var.karpenter.repro.replicas
      selector = {
        matchLabels = {
          app = "issue-25-burst"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "issue-25-burst"
          }
        }
        spec = {
          nodeSelector = {
            "karpenter.sh/nodepool" = var.karpenter.nodepool.name
          }
          tolerations = [
            {
              operator = "Exists"
            }
          ]
          containers = [
            {
              name    = "main"
              image   = var.karpenter.repro.image
              command = ["sh", "-c", "sleep ${var.karpenter.repro.sleep_seconds}"]
              resources = {
                requests = {
                  cpu    = var.karpenter.repro.cpu
                  memory = var.karpenter.repro.memory
                }
              }
            }
          ]
        }
      }
    }
  }) : null
}

resource "local_file" "karpenter_values" {
  count    = local.karpenter_enabled ? 1 : 0
  filename = "${path.module}/generated/karpenter-values.yaml"
  content  = local.karpenter_values_content
}

resource "local_file" "karpenter_ocinodeclass" {
  count    = local.karpenter_enabled ? 1 : 0
  filename = "${path.module}/generated/ocinodeclass.yaml"
  content  = local.karpenter_ocinodeclass_content
}

resource "local_file" "karpenter_nodepool" {
  count    = local.karpenter_enabled ? 1 : 0
  filename = "${path.module}/generated/nodepool.yaml"
  content  = local.karpenter_nodepool_content
}

resource "local_file" "karpenter_repro_workload" {
  count    = local.karpenter_enabled && try(var.karpenter.repro.enabled, false) ? 1 : 0
  filename = "${path.module}/generated/repro-workload.yaml"
  content  = local.karpenter_repro_workload_content
}

resource "local_file" "karpenter_collect_debug" {
  count    = local.karpenter_enabled ? 1 : 0
  filename = "${path.module}/generated/collect-debug.sh"
  content = templatefile("${path.module}/karpenter/collect-debug.sh.tftpl", {
    namespace = var.karpenter.namespace
  })
  file_permission = "0755"
}

output "karpenter" {
  value = local.karpenter_enabled ? {
    values_file             = try(local_file.karpenter_values[0].filename, null)
    ocinodeclass_file       = try(local_file.karpenter_ocinodeclass[0].filename, null)
    nodepool_file           = try(local_file.karpenter_nodepool[0].filename, null)
    repro_workload_file     = try(local_file.karpenter_repro_workload[0].filename, null)
    collect_debug_file      = try(local_file.karpenter_collect_debug[0].filename, null)
    bastion_public_ip       = try(module.instances[var.karpenter.bastion_instance_name].public_ip, null)
    kubeconfig_ip_principal = try(module.kubeconfig[var.karpenter.cluster_name].kubeconfig_instance_principal, null)
    apiserver_endpoint      = local.karpenter_apiserver_endpoint
    install_command         = try("ssh opc@${module.instances[var.karpenter.bastion_instance_name].public_ip}", null)
  } : null
}
