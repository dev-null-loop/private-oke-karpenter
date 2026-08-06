variable "karpenter" {
  description = "OCI Karpenter / KPO install and optional synthetic test workload settings"
  type = object({
    enabled                  = bool
    namespace                = optional(string, "karpenter")
    chart_version            = string
    release_name             = optional(string, "karpenter")
    cluster                  = string
    cluster_compartment      = string
    vcn_compartment          = string
    oci_vcn_ip_native        = bool
    ip_families              = optional(list(string), ["IPv4"])
    install_via_bastion      = optional(bool, true)
    bastion_instance         = optional(string, "bastion")
    bastion_kubeconfig_iam = optional(object({
      enabled               = optional(bool, true)
      bastion_compartment   = optional(string)
      dynamic_group         = optional(string, "kubeconfig_bastion")
      policy                = optional(string, "kubeconfig_bastion_cluster")
      matching_rule         = optional(string)
      manage_cluster_family = optional(bool, true)
    }), {})
    gitops = optional(object({
      repo_url             = optional(string, "https://github.com/dev-null-loop/private-oke-karpenter.git")
      revision             = optional(string, "main")
      argocd_namespace     = optional(string, "argocd")
      argocd_release_name  = optional(string, "argocd")
      argocd_chart_version = optional(string, "8.4.0")
      root_app             = optional(string, "root")
      chart_app            = optional(string, "karpenter-chart")
      manifests_app        = optional(string, "karpenter-manifests")
      repository_secret    = optional(string, "")
    }), {})
    node_pool = string
    iam = optional(object({
      enabled                     = optional(bool, true)
      policy_compartment          = optional(string)
      node_compartment            = optional(string)
      service_account             = optional(string, "karpenter")
      dynamic_group               = optional(string, "kpo_nodes")
      controller_policy           = optional(string, "kpo_controller")
      enable_capacity_reservation = optional(bool, false)
      enable_compute_cluster      = optional(bool, false)
      enable_cluster_pg           = optional(bool, false)
      enable_defined_tags         = optional(bool, false)
    }), {})
    nodepool = object({
      name                     = string
      cpu_limit                = number
      memory_limit             = optional(string)
      expire_after             = optional(string, "Never")
      termination_grace_period = optional(string, "120m")
      capacity_types           = optional(list(string), ["on-demand"])
      instance_shapes          = list(string)
      consolidation_policy     = optional(string, "WhenEmpty")
      consolidate_after        = optional(string, "60m")
      budget_nodes             = optional(string, "5%")
    })
    ocinodeclass = object({
      name = string
      shape_configs = optional(list(object({
        ocpus                     = number
        memory_in_gbs             = number
        baseline_ocpu_utilization = optional(string)
      })), [])
      image_config = object({
        image_type        = optional(string, "OKEImage")
        image_id          = optional(string)
        os_filter         = optional(string)
        os_version_filter = optional(string)
      })
      primary_subnet      = string
      primary_vnic_config = optional(object({
        assign_public_ip       = optional(bool)
        skip_source_dest_check = optional(bool)
      }), {})
      pod_subnets     = optional(list(string), [])
      pod_nsg_names    = optional(list(string), [])
      secondary_vnic_config = optional(object({
        assign_public_ip       = optional(bool)
        skip_source_dest_check = optional(bool)
      }), {})
      secondary_vnic_ip_count      = optional(number)
      use_same_node_and_pod_subnet = optional(bool, false)
    })
    test_workload = optional(object({
      name          = optional(string, "karpenter-test-workload")
      enabled       = optional(bool, false)
      replicas      = optional(number, 50)
      cpu           = optional(string, "2")
      memory        = optional(string, "4Gi")
      image         = optional(string, "busybox:1.36")
      sleep_seconds = optional(number, 3600)
    }), { enabled = false })
  })
  validation {
    condition = (
      !var.karpenter.enabled ||
      !var.karpenter.oci_vcn_ip_native ||
      var.karpenter.ocinodeclass.secondary_vnic_ip_count == null ||
      var.karpenter.ocinodeclass.use_same_node_and_pod_subnet ||
      length(var.karpenter.ocinodeclass.pod_subnets) > 0
    )
    error_message = "When OCI VCN-native secondary VNIC pod networking is enabled with separate pod subnets, set karpenter.ocinodeclass.pod_subnets or explicitly opt into use_same_node_and_pod_subnet = true."
  }
  default = {
    enabled                  = false
    chart_version            = "1.1.0"
    cluster                  = "c"
    cluster_compartment      = "dev"
    vcn_compartment          = "dev"
    oci_vcn_ip_native        = true
    bastion_kubeconfig_iam = {
      enabled = true
    }
    gitops = {}
    node_pool      = "n"
    iam = {
      enabled = true
    }
    nodepool = {
      name            = "karpenter-general"
      cpu_limit       = 64
      memory_limit    = "256Gi"
      instance_shapes = ["VM.Standard.E3.Flex"]
    }
    ocinodeclass = {
      name                  = "karpenter-general"
      image_config          = {}
      primary_subnet        = "nodes"
      primary_vnic_config   = {}
      secondary_vnic_config = {}
    }
  }
}
