variable "vcns" {
  type = map(object({
    cidr_blocks    = list(string)
    display_name   = string
    dns_label      = string
    compartment    = string
    is_ipv6enabled = optional(bool)
  }))

  validation {
    condition     = alltrue([for item in var.vcns : length(item.cidr_blocks) > 0])
    error_message = "VCN cidr blocks list cannot be empty."
  }
}

variable "internet_gateways" {
  type = map(object({
    display_name = optional(string)
    vcn          = string
  }))
  default = {}
}

variable "nat_gateways" {
  type = map(object({
    display_name = string
    vcn          = string
  }))
  default = {}
}

variable "service_gateways" {
  description = "service gateway parameters"
  type = map(object({
    display_name = string
    vcn          = string
  }))
  default = {}
}

variable "security_lists" {
  description = "security list parameters"
  type = map(object({
    vcn          = string
    display_name = optional(string)
    egress_rules = list(object({
      description      = optional(string)
      stateless        = optional(bool, false)
      protocol         = string
      destination      = string
      destination_type = string
      tcp_options = optional(object({
        min = number
        max = number
      }))
      udp_options = optional(object({
        min = number
        max = number
      }))
      icmp_options = optional(object({
        type = number
        code = number
      }))
    }))
    ingress_rules = list(object({
      stateless   = optional(bool, false)
      protocol    = string
      source      = string
      source_type = string
      tcp_options = optional(object({
        min = number
        max = number
      }))
      udp_options = optional(object({
        min = number
        max = number
      }))
      icmp_options = optional(object({
        type = number
        code = number
      }))
    }))
  }))
  default = {}
}

variable "route_tables" {
  type = map(object({
    vcn          = string
    display_name = string
    route_rules = list(object({
      description         = optional(string)
      network_entity_name = string
      destination         = string
      destination_type    = optional(string)
    }))
  }))
  default = {}
}

variable "subnets" {
  type = map(object({
    compartment                = string
    display_name               = string
    cidr_block                 = string
    dns_label                  = string
    prohibit_internet_ingress  = optional(bool)
    prohibit_public_ip_on_vnic = bool
    security_lists             = optional(list(string), [])
    route_table                = optional(string)
    vcn                        = string
  }))
  default = {}
}

variable "instances" {
  description = "instance configuration"
  type = map(object({
    availability_domain = number
    compartment         = string
    create_vnic_details = object({
      assign_public_ip = optional(bool, false)
      subnet           = string
      subnet_id        = optional(string)
    })
    display_name = string
    shape        = string
    shape_config = object({
      ocpus         = number
      memory_in_gbs = number
    })
    cloud_init = optional(list(object({
      filename     = optional(string)
      content      = optional(string)
      content_type = optional(string)
      vars         = optional(map(string))
    })), [])
    source_details = object({
      source_name = string
      source_type = optional(string, "image")
    })
    ssh_public_keys = list(string)
    state           = optional(string, "RUNNING")
    managed_cluster = string
  }))
  validation {
    condition     = alltrue([for i in var.instances : can(regex("(Oracle-Linux-|Windows-Server-).*", i.source_details.source_name))])
    error_message = "Error: Invalid image name..."
  }
  default = {}
}

variable "source_ids" {
  description = "map with image names and ocids"
  type        = map(string)
}
