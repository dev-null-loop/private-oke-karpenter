variable "instances" {
  description = "instance configuration"
  type = map(object({
    availability_domain = number
    compartment_name    = string
    create_vnic_details = object({
      assign_public_ip = optional(bool, false)
      subnet_name      = string
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
