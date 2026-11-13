output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA bundle for Kubernetes and Helm providers."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Running Kubernetes version of the control plane."
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (kept for IRSA-based third-party charts)."
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group shared by managed and Karpenter-provisioned nodes."
  value       = module.eks.node_security_group_id
}

output "secrets_kms_key_arn" {
  description = "KMS key ARN used for Kubernetes Secrets envelope encryption."
  value       = module.eks.kms_key_arn
}
