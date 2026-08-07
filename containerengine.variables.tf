variable "clusters" {
  type = map(object({
    compartment        = string
    name               = string
    kubernetes_version = string
    vcn                = string
    cluster_pod_network_options = object({
      cni_type = string
    })
    endpoint_config = object({
      subnet               = string
      is_public_ip_enabled = bool
    })
    options = optional(object({
      service_lb_subnets = optional(list(string), [])
      open_id_connect_discovery = optional(object({
        is_open_id_connect_discovery_enabled = optional(bool)
      }))
    }), {})
  }))
  default = {}
}

variable "node_pools" {
  type = map(object({
    compartment = string
    cluster     = string
    name        = string
    node_shape  = string
    node_shape_config = optional(object({
      ocpus         = optional(number)
      memory_in_gbs = optional(number)
    }))
    kubernetes_version = string
    ubuntu_release     = optional(string)
    ssh_public_key     = optional(string)
    node_config_details = object({
      placement_configs = list(object({
        availability_domain     = number
        fault_domains           = optional(list(number), [])
        subnet                  = string
        capacity_reservation_id = optional(string)
      }))
      size                                = number
      is_pv_encryption_in_transit_enabled = optional(bool)
      kms_key_id                          = optional(string)
      node_pool_pod_network_option_details = object({
        cni_type          = string
        max_pods_per_node = optional(number)
        pod_subnets       = optional(list(string), [])
        pod_nsg_ids       = optional(list(string))
      })
      defined_tags  = optional(map(string))
      freeform_tags = optional(map(string))
      nsg_ids       = optional(list(string))
    })
    node_source_details = object({
      boot_volume_size_in_gbs = optional(number)
      image_name              = string
      source_type             = optional(string)
    })
    cloud_init = optional(list(object({
      filename     = optional(string)
      content      = optional(string)
      content_type = optional(string, "text/x-shellscript")
      vars         = optional(map(string), {})
    })), [])
    node_metadata = optional(map(string))
    node_eviction_node_pool_settings = optional(object({
      eviction_grace_duration              = optional(string)
      is_force_delete_after_grace_duration = optional(bool)
    }))
    node_pool_cycling_details = optional(object({
      is_node_cycling_enabled = optional(bool)
      maximum_surge           = optional(number)
      maximum_unavailable     = optional(number)
    }))
  }))
  validation {
    condition = alltrue(flatten([
      for np in values(var.node_pools) : [
        for part in np.cloud_init :
        (part.filename != null) != (part.content != null)
      ]
    ]))
    error_message = "Each node_pools.cloud_init item must set exactly one of filename or content."
  }
  default = {}
}

variable "oke_worker_node_image_ids" {
  description = "(Optional) map of OKE worker node images and ocids"
  type        = map(string)
  default     = {}
}
