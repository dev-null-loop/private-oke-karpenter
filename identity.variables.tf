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
