output "values_content" {
  sensitive = true
  value     = var.karpenter.enabled ? local.values_content : null
}

output "ocinodeclass_content" {
  sensitive = true
  value     = var.karpenter.enabled ? local.ocinodeclass_content : null
}

output "nodepool_content" {
  sensitive = true
  value     = var.karpenter.enabled ? local.nodepool_content : null
}

output "test_workload_content" {
  sensitive = true
  value     = var.karpenter.enabled && var.karpenter.test_workload.enabled ? local.test_workload_content : null
}

output "values_file" {
  value = var.karpenter.enabled ? local_file.values[0].filename : null
}

output "ocinodeclass_file" {
  value = var.karpenter.enabled ? local_file.ocinodeclass[0].filename : null
}

output "nodepool_file" {
  value = var.karpenter.enabled ? local_file.nodepool[0].filename : null
}

output "test_workload_file" {
  value = var.karpenter.enabled && var.karpenter.test_workload.enabled ? local_file.test_workload[0].filename : null
}

output "collect_debug_file" {
  value = var.karpenter.enabled ? local_file.collect_debug[0].filename : null
}
