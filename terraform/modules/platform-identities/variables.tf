variable "cluster_name" {
  description = "EKS cluster name that the Pod Identity associations are created against."
  type        = string
}

variable "hosted_zone_arns" {
  description = "Route53 hosted zone ARNs ExternalDNS may modify. Scope to the platform's own zones."
  type        = list(string)

  validation {
    condition     = length(var.hosted_zone_arns) > 0 && alltrue([for a in var.hosted_zone_arns : can(regex("^arn:aws:route53:::hostedzone/", a))])
    error_message = "hosted_zone_arns must contain Route53 hosted zone ARNs, for example arn:aws:route53:::hostedzone/Z0123456789ABC."
  }
}

variable "ebs_kms_key_arns" {
  description = "KMS key ARNs the EBS CSI driver may use for encrypted volumes. Empty means the AWS managed key for EBS."
  type        = list(string)
  default     = []
}
