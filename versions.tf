terraform {
  required_providers {
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    oci = {
      source  = "oracle/oci"
      version = ">= 8.14.0"
    }
  }
  required_version = ">= 1.5.7"
}
