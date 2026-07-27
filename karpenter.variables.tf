variable "karpenter" {
  description = "OCI Karpenter / KPO install and optional synthetic test workload settings"
  type = object({
    enabled                  = bool
    namespace                = optional(string, "karpenter")
    chart_version            = string
    release_name             = optional(string, "karpenter")
    cluster_name             = string
    cluster_compartment_name = string
    vcn_compartment_name     = string
    oci_vcn_ip_native        = bool
    ip_families              = optional(list(string), ["IPv4"])
    install_via_bastion      = optional(bool, true)
    bastion_instance_name    = optional(string, "bastion")
    bastion_kubeconfig_iam = optional(object({
      enabled                  = optional(bool, true)
      bastion_compartment_name = optional(string)
      dynamic_group_name       = optional(string, "kubeconfig_bastion")
      policy_name              = optional(string, "kubeconfig_bastion_cluster")
      matching_rule            = optional(string)
      manage_cluster_family    = optional(bool, true)
    }), {})
    node_pool_name = string
    iam = optional(object({
      enabled                     = optional(bool, true)
      policy_compartment_name     = optional(string)
      node_compartment_name       = optional(string)
      service_account             = optional(string, "karpenter")
      dynamic_group_name          = optional(string, "kpo_nodes")
      controller_policy_name      = optional(string, "kpo_controller")
      cluster_join_policy_name    = optional(string, "kpo_cluster_join")
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
      primary_subnet_name = string
      primary_vnic_config = optional(object({
        assign_public_ip       = optional(bool)
        skip_source_dest_check = optional(bool)
      }), {})
      pod_subnet_names = optional(list(string), [])
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
      try(var.karpenter.ocinodeclass.secondary_vnic_ip_count, null) == null ||
      try(var.karpenter.ocinodeclass.use_same_node_and_pod_subnet, false) ||
      length(try(var.karpenter.ocinodeclass.pod_subnet_names, [])) > 0
    )
    error_message = "When OCI VCN-native secondary VNIC pod networking is enabled with separate pod subnets, set karpenter.ocinodeclass.pod_subnet_names or explicitly opt into use_same_node_and_pod_subnet = true."
  }
  default = {
    enabled                  = false
    chart_version            = "1.1.0"
    cluster_name             = "c"
    cluster_compartment_name = "dev"
    vcn_compartment_name     = "dev"
    oci_vcn_ip_native        = true
    bastion_kubeconfig_iam = {
      enabled = true
    }
    node_pool_name = "n"
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
      primary_subnet_name   = "nodes"
      primary_vnic_config   = {}
      secondary_vnic_config = {}
    }
  }
}
