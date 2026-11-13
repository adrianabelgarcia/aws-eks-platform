variable "environment" {
  description = "Environment name. Must match the directory this root lives in."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "AWS region for the platform."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier such as us-east-1."
  }
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane version (1.NN)."
  type        = string

  validation {
    condition     = can(regex("^1\\.(29|3[0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported EKS minor version in the form 1.NN."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block (/16)."
  type        = string
}

variable "availability_zones" {
  description = "Availability zone names the VPC and cluster span (pinned, never discovered)."
  type        = list(string)
}

variable "nat_strategy" {
  description = "NAT topology: single (staging) or per_az (prod)."
  type        = string

  validation {
    condition     = contains(["single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be single or per_az."
  }
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Use the CI runner egress range and operator VPN CIDR."
  type        = list(string)
}

variable "platform_admin_role_arn" {
  description = "IAM role ARN for human platform administrators (cluster admin)."
  type        = string
}

variable "terraform_role_arn" {
  description = "IAM role ARN assumed by the CI pipeline (cluster admin, needed for Helm installs)."
  type        = string
}

variable "auditor_role_arn" {
  description = "IAM role ARN for read-only cluster access."
  type        = string
}

variable "hosted_zone_arns" {
  description = "Route53 hosted zone ARNs ExternalDNS may manage."
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane and VPC flow logs."
  type        = number
  default     = 365
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental deletion."
  type        = bool
  default     = false
}

variable "system_node_instance_types" {
  description = "Instance types for the tainted system node group."
  type        = list(string)
  default     = ["m7g.large"]
}

variable "system_node_min_size" {
  description = "System node group minimum size."
  type        = number
  default     = 2
}

variable "system_node_desired_size" {
  description = "System node group desired size."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "System node group maximum size."
  type        = number
  default     = 3
}

variable "karpenter_replicas" {
  description = "Karpenter controller replicas."
  type        = number
  default     = 1
}

variable "argocd_ha" {
  description = "Argo CD HA mode (two server and repo-server replicas)."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "GitOps repository URL watched by Argo CD."
  type        = string
  default     = "https://github.com/adrianabelgarcia/aws-eks-platform.git"
}

variable "gitops_revision" {
  description = "Git revision the Argo CD root application tracks."
  type        = string
  default     = "main"
}
