variable "karpenter" {
  description = "OCI Karpenter / KPO infrastructure prerequisites and IAM settings"
  type = object({
    enabled             = bool
    namespace           = optional(string, "karpenter")
    cluster             = string
    cluster_compartment = string
    image_type          = optional(string, "OKEImage")
    bootstrap_mode      = optional(string, "metadata")
    image_source        = optional(string, "filter")
    node_image          = optional(string)
    controller_image = optional(object({
      registry         = string
      repository_name  = string
      tag              = string
      pull_secret_name = optional(string)
    }))
    image_filter = optional(object({
      compartment = optional(string)
      os          = string
      os_version  = string
    }))
    shape = optional(object({
      ocpus         = optional(number, 8)
      memory_in_gbs = optional(number, 32)
    }), {})
    pod_ip_count  = optional(number, 8)
    capacityType  = optional(string, "on-demand")
    instanceShape = optional(string, "VM.Standard.E3.Flex")
    limits = optional(object({
      cpu    = optional(number, 32)
      memory = optional(string, "128Gi")
    }), {})
    ssh_public_key   = optional(string)
    node_subnet      = optional(string, "nodes")
    pod_subnet       = optional(string, "kpo_pods")
    assign_public_ip = optional(bool, true)
    bastion_instance = optional(string, "bastion")
    bastion_kubeconfig_iam = optional(object({
      enabled             = optional(bool, true)
      bastion_compartment = optional(string)
      policy              = optional(string, "kubeconfig_bastion_cluster")
    }), {})
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
  })
  default = {
    enabled             = false
    cluster             = "c"
    cluster_compartment = "dev"
  }

  validation {
    condition     = contains(["OKEImage", "Custom"], try(var.karpenter.image_type, "OKEImage"))
    error_message = "karpenter.image_type must be OKEImage or Custom."
  }

  validation {
    condition     = contains(["on-demand", "reserved", "preemptible"], try(var.karpenter.capacityType, "on-demand"))
    error_message = "karpenter.capacityType must be on-demand, reserved, or preemptible."
  }

  validation {
    condition     = contains(["native", "prebootstrap", "metadata"], try(var.karpenter.bootstrap_mode, "prebootstrap"))
    error_message = "karpenter.bootstrap_mode must be native, prebootstrap, or metadata."
  }

  validation {
    condition     = contains(["filter", "image_id"], try(var.karpenter.image_source, "filter"))
    error_message = "karpenter.image_source must be filter or image_id."
  }

  validation {
    condition = !(
      try(var.karpenter.image_type, "OKEImage") == "Custom" &&
      try(var.karpenter.bootstrap_mode, "prebootstrap") != "metadata"
    )
    error_message = "karpenter.image_type = Custom requires karpenter.bootstrap_mode = metadata."
  }

  validation {
    condition = !(
      try(var.karpenter.image_source, "filter") == "filter" &&
      var.karpenter.image_filter == null
    )
    error_message = "karpenter.image_source = filter requires karpenter.image_filter."
  }

  validation {
    condition = !(
      try(var.karpenter.image_source, "filter") == "image_id" &&
      try(var.karpenter.node_image, null) == null
    )
    error_message = "karpenter.image_source = image_id requires karpenter.node_image."
  }

}
