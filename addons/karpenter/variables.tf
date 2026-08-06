variable "karpenter" {
  type = object({
    enabled                = bool
    namespace              = string
    chart_version          = string
    release_name           = string
    cluster_compartment_id = string
    vcn_compartment_id     = string
    apiserver_endpoint     = string
    oci_vcn_ip_native      = bool
    ip_families            = list(string)
    ocinodeclass = object({
      name                = string
      ssh_authorized_keys = optional(list(string), [])
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
      primary_subnet_id = string
      primary_vnic_config = optional(object({
        assign_public_ip       = optional(bool)
        skip_source_dest_check = optional(bool)
      }), {})
      secondary_vnic_configs = optional(list(object({
        subnet_id              = string
        ip_count               = number
        assign_public_ip       = optional(bool)
        skip_source_dest_check = optional(bool)
      })), [])
    })
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
    test_workload = object({
      name          = optional(string, "karpenter-test-workload")
      enabled       = optional(bool, false)
      replicas      = optional(number, 50)
      cpu           = optional(string, "2")
      memory        = optional(string, "4Gi")
      image         = optional(string, "busybox:1.36")
      sleep_seconds = optional(number, 3600)
    })
  })
}
