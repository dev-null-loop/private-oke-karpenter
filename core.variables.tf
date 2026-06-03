variable "instances" {
  description = "instance configuration"
  type = map(object({
    availability_domain = number
    assign_public_ip    = optional(bool)
    compartment_name    = string
    display_name        = optional(string)
    shape               = string
    shape_config = optional(object({
      baseline_ocpu_utilization = optional(string)
      memory_in_gbs             = optional(number)
      nvmes                     = optional(number)
      ocpus                     = optional(number)
      vcpus                     = optional(number)
    }))
    boot_volume_size = optional(number)
    cloud_init = optional(list(object({
      filename     = optional(string)
      content      = optional(string)
      content_type = optional(string)
      vars         = optional(map(string))
    })), [])
    fault_domain = optional(number)
    nsg_ids      = optional(list(string))
    private_ip   = optional(string)
    create_vnic_details = optional(object({
      assign_ipv6ip             = optional(bool)
      assign_public_ip          = optional(bool)
      assign_private_dns_record = optional(bool)
      defined_tags              = optional(map(string))
      display_name              = optional(string)
      freeform_tags             = optional(map(string))
      hostname_label            = optional(string)
      nsg_names                 = optional(list(string))
      private_ip                = optional(string)
      security_attributes       = optional(map(string))
      skip_source_dest_check    = optional(bool)
      subnet_name               = optional(string)
      subnet_id                 = optional(string)
    }))
    skip_source_dest_check = optional(bool)
    ssh_public_keys        = optional(list(string))
    preserve_boot_volume   = optional(bool)
    encrypt_in_transit     = optional(bool)
    source_details = optional(object({
      source_name             = string
      source_type             = optional(string)
      boot_volume_size_in_gbs = optional(number)
      boot_volume_vpus_per_gb = optional(number)
      kms_key_id              = optional(string)
    }))
    managed_cluster = optional(string)
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
