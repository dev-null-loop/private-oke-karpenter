locals {
  test_workload_name = var.test_workload.name
  gitops_base_path   = "${path.root}/gitops/clusters/private-oke-karpenter"
  gitops_karpenter_path = "${local.gitops_base_path}/karpenter"

  values_content = templatefile("${path.module}/values.yaml.tftpl", {
    cluster_compartment_id = var.cluster_compartment_id
    vcn_compartment_id     = var.vcn_compartment_id
    apiserver_endpoint     = var.apiserver_endpoint
    oci_vcn_ip_native      = var.oci_vcn_ip_native
    ip_families            = var.ip_families
  })

  ocinodeclass_shape_configs = [
    for cfg in var.ocinodeclass.shape_configs : merge(
      {
        ocpus       = cfg.ocpus
        memoryInGbs = cfg.memory_in_gbs
      },
      {
        for k, v in {
          baselineOcpuUtilization = cfg.baseline_ocpu_utilization
        } : k => v if v != null
      }
    )
  ]

  ocinodeclass_image_filter = {
    for k, v in {
      osFilter        = var.ocinodeclass.image_config.os_filter
      osVersionFilter = var.ocinodeclass.image_config.os_version_filter
    } : k => v if v != null
  }

  ocinodeclass_image_config = merge(
    {
      imageType = var.ocinodeclass.image_config.image_type
    },
    var.ocinodeclass.image_config.image_id != null ? {
      imageId = var.ocinodeclass.image_config.image_id
    } : {},
    var.ocinodeclass.image_config.image_id == null && length(local.ocinodeclass_image_filter) > 0 ? {
      imageFilter = local.ocinodeclass_image_filter
    } : {}
  )

  ocinodeclass_primary_vnic_config = merge(
    {
      subnetConfig = {
        subnetId = var.ocinodeclass.primary_subnet_id
      }
    },
    {
      for k, v in {
        assignPublicIp       = var.ocinodeclass.primary_vnic_config.assign_public_ip
        skipSourceDestCheck  = var.ocinodeclass.primary_vnic_config.skip_source_dest_check
      } : k => v if v != null
    }
  )

  ocinodeclass_secondary_vnic_configs = [
    for cfg in var.ocinodeclass.secondary_vnic_configs : merge(
      {
        subnetConfig = {
          subnetId = cfg.subnet_id
        }
        ipCount = cfg.ip_count
      },
      {
        for k, v in {
          assignPublicIp      = cfg.assign_public_ip
          skipSourceDestCheck = cfg.skip_source_dest_check
        } : k => v if v != null
      }
    )
  ]

  ocinodeclass_spec = merge(
    length(local.ocinodeclass_shape_configs) > 0 ? {
      shapeConfigs = local.ocinodeclass_shape_configs
    } : {},
    {
      volumeConfig = {
        bootVolumeConfig = {
          imageConfig = local.ocinodeclass_image_config
        }
      }
      networkConfig = merge(
        {
          primaryVnicConfig = local.ocinodeclass_primary_vnic_config
        },
        length(local.ocinodeclass_secondary_vnic_configs) > 0 ? {
          secondaryVnicConfigs = local.ocinodeclass_secondary_vnic_configs
        } : {}
      )
    }
  )

  ocinodeclass_content = yamlencode({
    apiVersion = "oci.oraclecloud.com/v1beta1"
    kind       = "OCINodeClass"
    metadata = {
      name = var.ocinodeclass.name
    }
    spec = local.ocinodeclass_spec
  })

  nodepool_limits = merge(
    {
      cpu = var.nodepool.cpu_limit
    },
    {
      for k, v in {
        memory = var.nodepool.memory_limit
      } : k => v if v != null
    }
  )

  nodepool_content = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = var.nodepool.name
    }
    spec = {
      template = {
        spec = {
          expireAfter            = var.nodepool.expire_after
          terminationGracePeriod = var.nodepool.termination_grace_period
          nodeClassRef = {
            group = "oci.oraclecloud.com"
            kind  = "OCINodeClass"
            name  = var.ocinodeclass.name
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.nodepool.capacity_types
            },
            {
              key      = "oci.oraclecloud.com/instance-shape"
              operator = "In"
              values   = var.nodepool.instance_shapes
            }
          ]
        }
      }
      disruption = {
        budgets = [
          {
            nodes = var.nodepool.budget_nodes
          }
        ]
        consolidateAfter    = var.nodepool.consolidate_after
        consolidationPolicy = var.nodepool.consolidation_policy
      }
      limits = local.nodepool_limits
    }
  })

  test_workload_content = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name = local.test_workload_name
    }
    spec = {
      replicas = var.test_workload.replicas
      selector = {
        matchLabels = {
          app = local.test_workload_name
        }
      }
      template = {
        metadata = {
          labels = {
            app = local.test_workload_name
          }
        }
        spec = {
          nodeSelector = {
            "karpenter.sh/nodepool" = var.nodepool.name
          }
          tolerations = [
            {
              operator = "Exists"
            }
          ]
          containers = [
            {
              name    = "main"
              image   = var.test_workload.image
              command = ["sh", "-c", "sleep ${var.test_workload.sleep_seconds}"]
              resources = {
                requests = {
                  cpu    = var.test_workload.cpu
                  memory = var.test_workload.memory
                }
              }
            }
          ]
        }
      }
    }
  })

  gitops_karpenter_kustomization_content = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = concat(
      [
        "ocinodeclass.yaml",
        "nodepool.yaml",
      ],
      var.test_workload.enabled ? ["test-workload.yaml"] : []
    )
  })

  gitops_chart_app_content = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.gitops.chart_app
      namespace = var.gitops.argocd_namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "0"
      }
    }
    spec = {
      project = "default"
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      sources = [
        {
          repoURL        = "https://oracle.github.io/karpenter-provider-oci/charts"
          chart          = "karpenter"
          targetRevision = var.chart_version
          helm = {
            valueFiles = [
              "$values/gitops/clusters/private-oke-karpenter/karpenter/values.yaml"
            ]
          }
        },
        {
          repoURL        = var.gitops.repo_url
          targetRevision = var.gitops.revision
          ref            = "values"
        }
      ]
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  })

  gitops_manifests_app_content = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.gitops.manifests_app
      namespace = var.gitops.argocd_namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "1"
      }
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops.repo_url
        targetRevision = var.gitops.revision
        path           = "gitops/clusters/private-oke-karpenter/karpenter"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })
}

resource "local_file" "values" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/values.yaml"
  content  = local.values_content
}

resource "local_file" "ocinodeclass" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/ocinodeclass.yaml"
  content  = local.ocinodeclass_content
}

resource "local_file" "nodepool" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/nodepool.yaml"
  content  = local.nodepool_content
}

resource "local_file" "test_workload" {
  count    = var.enabled && var.test_workload.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/test-workload.yaml"
  content  = local.test_workload_content
}

resource "local_file" "collect_debug" {
  count           = var.enabled ? 1 : 0
  filename        = "${local.gitops_karpenter_path}/collect-debug.sh"
  content         = templatefile("${path.module}/collect-debug.sh.tftpl", { namespace = var.namespace })
  file_permission = "0755"
}

resource "local_file" "gitops_karpenter_kustomization" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/kustomization.yaml"
  content  = local.gitops_karpenter_kustomization_content
}

resource "local_file" "gitops_chart_application" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_base_path}/applications/karpenter-chart.yaml"
  content  = local.gitops_chart_app_content
}

resource "local_file" "gitops_manifests_application" {
  count    = var.enabled ? 1 : 0
  filename = "${local.gitops_base_path}/applications/karpenter-manifests.yaml"
  content  = local.gitops_manifests_app_content
}
