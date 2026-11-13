output "cluster_name" {
  description = "EKS cluster name."
  value       = module.platform.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint (private from inside the VPC)."
  value       = module.platform.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID (copy into the AWS Load Balancer Controller values in gitops/clusters/staging)."
  value       = module.platform.vpc_id
}

output "karpenter_node_role_name" {
  description = "Karpenter node role name (must match gitops/platform/karpenter/overlays/staging)."
  value       = module.platform.karpenter_node_role_name
}

output "karpenter_interruption_queue" {
  description = "Karpenter interruption queue name."
  value       = module.platform.karpenter_interruption_queue
}
