output "node_iam_role_name" {
  description = "IAM role name attached to Karpenter-provisioned nodes. Referenced by the gitops EC2NodeClass."
  value       = module.karpenter.node_iam_role_name
}

output "interruption_queue_name" {
  description = "SQS queue receiving Spot interruption and rebalance events."
  value       = module.karpenter.queue_name
}

output "controller_role_arn" {
  description = "IAM role ARN of the Karpenter controller (Pod Identity)."
  value       = module.karpenter.iam_role_arn
}
