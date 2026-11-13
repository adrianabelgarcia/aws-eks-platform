variable "cluster_name" {
  description = "EKS cluster name Karpenter manages capacity for."
  type        = string
}

variable "region" {
  description = "AWS region. Set explicitly because nodes enforce IMDS hop limit 1, so the controller cannot discover it from metadata."
  type        = string
  default     = "us-east-1"
}

variable "karpenter_version" {
  description = "Karpenter chart version (karpenter and karpenter-crd charts share a version)."
  type        = string
  default     = "1.15.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.karpenter_version))
    error_message = "karpenter_version must be an exact semantic version, for example 1.15.2."
  }
}

variable "replicas" {
  description = "Karpenter controller replicas. Use 2 in prod for leader-election failover; 1 is fine in staging."
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 3
    error_message = "replicas must be between 1 and 3."
  }
}
