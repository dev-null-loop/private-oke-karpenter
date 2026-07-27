variable "clusters" {
  type = map(object({
    compartment_name   = string
    name               = string
    kubernetes_version = string
    vcn_name           = string
    cni_type           = string
    endpoint_config = optional(object({
      subnet_name          = string
      is_public_ip_enabled = bool
    }))
    options = optional(object({
      service_lb_subnet_names = optional(list(string), [])
      open_id_connect_discovery = optional(object({
        is_open_id_connect_discovery_enabled = optional(bool)
      }))
    }))
  }))
  default = {}
}

variable "node_pools" {
  type = map(object({
    compartment_name = string
    cluster_name     = string
    name             = string
    node_shape       = string
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
        subnet_name             = string
        capacity_reservation_id = optional(string)
      }))
      size                                = number
      is_pv_encryption_in_transit_enabled = optional(bool)
      kms_key_id                          = optional(string)
      node_pool_pod_network_option_details = optional(object({
        cni_type          = string
        max_pods_per_node = optional(number)
        pod_subnet_names  = optional(list(string), [])
        pod_nsg_ids       = optional(list(string))
      }))
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
      content_type = optional(string)
      vars         = optional(map(string))
    })), [])
    node_eviction_node_pool_settings = optional(object({
      eviction_grace_duration              = optional(string)
      is_force_delete_after_grace_duration = optional(bool)
    }))
  }))
  default = {}
}

variable "helm_releases" {
  type = map(object({
    chart            = string
    name             = string
    repository       = optional(string)
    chart_version    = optional(string)
    namespace        = optional(string)
    create_namespace = optional(bool)
    timeout          = optional(number)
    values           = optional(string)
  }))
  default = {}
}

variable "addons" {
  type = map(object({
    cluster_name              = string
    addon_name                = string
    configurations            = map(string)
    compartment_name          = optional(string)
    load_balancer_subnet_name = optional(string)
    min_nodes                 = optional(number)
    max_nodes                 = optional(number)
    node_pool_name            = optional(string)
    node_pool_tags            = optional(map(string))
  }))
  default = {}
}

variable "oke_worker_node_image_ids" {
  description = "(Optional) map of OKE worker node images and ocids"
  type        = map(string)
  default     = {}
}
