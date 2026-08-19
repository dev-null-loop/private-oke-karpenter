variable "karpenter" {
  description = "OCI Karpenter / KPO infrastructure prerequisites and IAM settings"
  type = object({
    enabled             = bool
    namespace           = optional(string, "karpenter")
    cluster             = string
    cluster_compartment = string
    node_image          = optional(string)
    ssh_public_key      = optional(string)
    node_subnet         = optional(string, "nodes")
    pod_subnet          = optional(string, "kpo_pods")
    assign_public_ip    = optional(bool, true)
    bastion_instance    = optional(string, "bastion")
    bastion_kubeconfig_iam = optional(object({
      bastion_compartment   = optional(string)
      policy                = optional(string, "kubeconfig_bastion_cluster")
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
}
