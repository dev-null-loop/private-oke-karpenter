data "oci_core_services" "svcs" {}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "cloudinit_config" "instances" {
  for_each      = local.instance_cloud_init_inputs
  gzip          = false
  base64_encode = false

  dynamic "part" {
    for_each = each.value.cloud_init
    iterator = p

    content {
      content_type = p.value.content_type
      filename     = p.value.filename != null ? basename(p.value.filename) : null
      content = (
        p.value.filename != null ?
        templatefile("${path.root}/${p.value.filename}", merge(each.value.cloud_init_vars, p.value.vars)) :
        templatestring(p.value.content, merge(each.value.cloud_init_vars, p.value.vars))
      )
      merge_type = "list(append)+dict(no_replace,recurse_list)+str(append)"
    }
  }
}
