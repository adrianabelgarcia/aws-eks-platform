output "key_arn" {
  description = "ARN of the KMS key used to encrypt CloudWatch log groups (VPC flow logs, EKS control plane logs)."
  value       = aws_kms_key.logs.arn
}
