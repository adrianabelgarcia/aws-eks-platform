output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA bundle (base64)."
  value       = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  description = "VPC ID. Needed by the AWS Load Balancer Controller values in gitops/clusters/<env>."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.network.private_subnet_ids
}

output "karpenter_node_role_name" {
  description = "Karpenter node IAM role name. Must match the EC2NodeClass role in gitops/platform/karpenter/overlays."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_interruption_queue" {
  description = "SQS interruption queue name."
  value       = module.karpenter.interruption_queue_name
}
