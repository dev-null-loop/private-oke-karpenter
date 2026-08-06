locals {
  test_workload_name    = var.karpenter.test_workload.name
  gitops_base_path      = "${path.root}/gitops/clusters/private-oke-karpenter"
  gitops_karpenter_path = "${local.gitops_base_path}/karpenter"
  ocinodeclass_user_data = base64encode(<<-EOT
    #!/usr/bin/env bash
    # Karpenter Provider OCI OKE bootstrap compatibility shim.
    #
    # Export OKE bootstrap metadata into the environment before running
    # Oracle's standard worker bootstrap entrypoint.

    set -o errexit
    set -o nounset
    set -o pipefail

    MD_URL="http://169.254.169.254/opc/v2/instance/metadata"
    AUTH_HDR="Authorization: Bearer Oracle"

    fetch_md() {
      local key="$1"
      curl -sfL -H "$${AUTH_HDR}" --connect-timeout 2 --max-time 5 "$${MD_URL}/$${key}" 2>/dev/null || true
    }

    CLUSTER_DNS="$(fetch_md kubedns_svc_ip)"
    KUBELET_EXTRA_ARGS="$(fetch_md kubelet-extra-args)"
    APISERVER_ENDPOINT="$(fetch_md apiserver_host)"
    KUBELET_CA_CERT="$(fetch_md cluster_ca_cert)"

    # OKE bootstrap expects the control-plane host without the Kubernetes API port.
    if [[ "$${APISERVER_ENDPOINT}" =~ ^\[(.*)\](:[0-9]+)?$ ]]; then
      APISERVER_ENDPOINT="$${BASH_REMATCH[1]}"
    elif [[ "$${APISERVER_ENDPOINT}" == *:* ]]; then
      APISERVER_ENDPOINT="$${APISERVER_ENDPOINT%%:*}"
    fi

    [ -n "$${CLUSTER_DNS}" ] && export CLUSTER_DNS
    [ -n "$${KUBELET_EXTRA_ARGS}" ] && export KUBELET_EXTRA_ARGS
    [ -n "$${APISERVER_ENDPOINT}" ] && export APISERVER_ENDPOINT
    [ -n "$${KUBELET_CA_CERT}" ] && export KUBELET_CA_CERT

    bash /etc/oke/oke-install.sh
  EOT
  )

  values_content = templatefile("${path.module}/values.yaml.tftpl", {
    cluster_compartment_id = var.karpenter.cluster_compartment_id
    vcn_compartment_id     = var.karpenter.vcn_compartment_id
    apiserver_endpoint     = var.karpenter.apiserver_endpoint
    oci_vcn_ip_native      = var.karpenter.oci_vcn_ip_native
    ip_families            = var.karpenter.ip_families
  })

  ocinodeclass_shape_configs = [
    for cfg in var.karpenter.ocinodeclass.shape_configs : merge(
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
      osFilter        = var.karpenter.ocinodeclass.image_config.os_filter
      osVersionFilter = var.karpenter.ocinodeclass.image_config.os_version_filter
    } : k => v if v != null
  }

  ocinodeclass_image_config = merge(
    {
      imageType = var.karpenter.ocinodeclass.image_config.image_type
    },
    var.karpenter.ocinodeclass.image_config.image_id != null ? {
      imageId = var.karpenter.ocinodeclass.image_config.image_id
    } : {},
    var.karpenter.ocinodeclass.image_config.image_id == null && length(local.ocinodeclass_image_filter) > 0 ? {
      imageFilter = local.ocinodeclass_image_filter
    } : {}
  )

  ocinodeclass_primary_vnic_config = merge(
    {
      subnetConfig = {
        subnetId = var.karpenter.ocinodeclass.primary_subnet_id
      }
    },
    {
      for k, v in {
        assignPublicIp      = var.karpenter.ocinodeclass.primary_vnic_config.assign_public_ip
        skipSourceDestCheck = var.karpenter.ocinodeclass.primary_vnic_config.skip_source_dest_check
      } : k => v if v != null
    }
  )

  ocinodeclass_secondary_vnic_configs = [
    for cfg in var.karpenter.ocinodeclass.secondary_vnic_configs : merge(
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
    length(var.karpenter.ocinodeclass.ssh_authorized_keys) > 0 ? {
      sshAuthorizedKeys = var.karpenter.ocinodeclass.ssh_authorized_keys
    } : {},
    {
      metadata = {
        user_data = local.ocinodeclass_user_data
      }
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
      name = var.karpenter.ocinodeclass.name
    }
    spec = local.ocinodeclass_spec
  })

  nodepool_limits = merge(
    {
      cpu = var.karpenter.nodepool.cpu_limit
    },
    {
      for k, v in {
        memory = var.karpenter.nodepool.memory_limit
      } : k => v if v != null
    }
  )

  nodepool_content = yamlencode({
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
      replicas = var.karpenter.test_workload.replicas
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
              image   = var.karpenter.test_workload.image
              command = ["sh", "-c", "sleep ${var.karpenter.test_workload.sleep_seconds}"]
              resources = {
                requests = {
                  cpu    = var.karpenter.test_workload.cpu
                  memory = var.karpenter.test_workload.memory
                }
              }
            }
          ]
        }
      }
    }
  })
}

resource "local_file" "values" {
  count    = var.karpenter.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/values.yaml"
  content  = local.values_content
}

resource "local_file" "ocinodeclass" {
  count    = var.karpenter.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/ocinodeclass.yaml"
  content  = local.ocinodeclass_content
}

resource "local_file" "nodepool" {
  count    = var.karpenter.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/nodepool.yaml"
  content  = local.nodepool_content
}

resource "local_file" "test_workload" {
  count    = var.karpenter.enabled && var.karpenter.test_workload.enabled ? 1 : 0
  filename = "${local.gitops_karpenter_path}/test-workload.yaml"
  content  = local.test_workload_content
}

resource "local_file" "collect_debug" {
  count           = var.karpenter.enabled ? 1 : 0
  filename        = "${local.gitops_karpenter_path}/collect-debug.sh"
  content         = templatefile("${path.module}/collect-debug.sh.tftpl", { namespace = var.karpenter.namespace })
  file_permission = "0755"
}
