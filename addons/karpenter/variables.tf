variable "enabled" {
  type = bool
}

variable "namespace" {
  type = string
}

variable "chart_version" {
  type = string
}

variable "release_name" {
  type = string
}

variable "gitops" {
  type = object({
    repo_url            = string
    revision            = string
    argocd_namespace    = string
    chart_app           = string
    manifests_app       = string
  })
}

variable "cluster_compartment_id" {
  type = string
}

variable "vcn_compartment_id" {
  type = string
}

variable "apiserver_endpoint" {
  type = string
}

variable "oci_vcn_ip_native" {
  type = bool
}

variable "ip_families" {
  type = list(string)
}

variable "ocinodeclass" {
  type = object({
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
}

variable "nodepool" {
  type = object({
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
}

variable "test_workload" {
  type = object({
    name          = optional(string, "karpenter-test-workload")
    enabled       = optional(bool, false)
    replicas      = optional(number, 50)
    cpu           = optional(string, "2")
    memory        = optional(string, "4Gi")
    image         = optional(string, "busybox:1.36")
    sleep_seconds = optional(number, 3600)
  })
}
