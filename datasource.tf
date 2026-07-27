data "oci_core_services" "svcs" {}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}
