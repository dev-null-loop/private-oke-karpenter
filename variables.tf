variable "tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
}

variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}
variable "home_region" {
  description = "OCI tenancy home region, required for IAM create/update/delete operations."
  type        = string
}
variable "compartment_ids" {
  type = map(string)
}

variable "vcns" {
  type = map(object({
    cidr_blocks      = list(string)
    display_name     = string
    dns_label        = string
    compartment_name = string
    is_ipv6enabled   = bool
  }))

  validation {
    condition     = alltrue([for item in var.vcns : length(item.cidr_blocks) > 0])
    error_message = "VCN cidr blocks list cannot be empty."
  }
}

variable "internet_gateways" {
  type = map(object({
    display_name = optional(string)
    vcn_name     = string
  }))
  default = {}
}

variable "nat_gateways" {
  type = map(object({
    display_name = string
    vcn_name     = string
  }))
  default = {}
}

variable "service_gateways" {
  description = "service gateway parameters"
  type = map(object({
    display_name = string
    vcn_name     = string
    service_name = optional(string, "services")
  }))
  default = {}
}

variable "security_lists" {
  description = "security list parameters"
  type = map(object({
    vcn_name     = string
    display_name = optional(string)
    egress_rules = list(object({
      description      = optional(string)
      stateless        = string
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
      stateless   = string
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
    vcn_name     = string
    display_name = string
    route_rules = list(object({
      description         = optional(string)
      network_entity_name = string
      destination         = string
      destination_type    = optional(string)
    }))
  }))
  #   validation {
  #   condition     = alltrue([for i in var.route_rules : can(regex("^(ig|sg|lpg|drg|ng|pip)_", i.network_entity_name))])
  #   error_message = "Error: A network_entity_name is prefixed with (ig|sg|lpg|drg|ng|pip)_(.*), where (.*) is the name of the object representing the network entity"
  # }

  # validation {
  #   condition = alltrue([for i in var.route_rules :
  #   can(regex("^(lpg_.*_(requestor|acceptor))$", i.network_entity_name)) if can(regex("^lpg_", i.network_entity_name))])
  #   error_message = "valid network_entity_names for local peering gateways are lpg_(.*)_(requestor|acceptor), where (.*) is the name of the object representing the lpg"
  # }
  default = {}
}

variable "subnets" {
  type = map(object({
    compartment_name           = string
    display_name               = string
    cidr_block                 = string
    dns_label                  = string
    prohibit_internet_ingress  = optional(bool)
    prohibit_public_ip_on_vnic = bool
    security_list_names        = optional(list(string), [])
    route_table_name           = optional(string)
    vcn_name                   = string
  }))
  default = {}
}

variable "virtual_node_pools" {}
