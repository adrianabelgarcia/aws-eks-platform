variable "environment" {
  description = "Environment name (staging or prod). Selects the GitOps root path."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name, for example acme-staging."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version, for example 1.34."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (/16)."
  type        = string
}

variable "availability_zones" {
  description = "Availability zone names the VPC and cluster span."
  type        = list(string)
}

variable "nat_strategy" {
  description = "single or per_az NAT gateways."
  type        = string
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
}

variable "platform_admin_role_arn" {
  description = "IAM role for human platform administrators."
  type        = string
}

variable "terraform_role_arn" {
  description = "IAM role Terraform runs as (the CI OIDC role). Needs cluster admin for Helm."
  type        = string
}

variable "auditor_role_arn" {
  description = "IAM role with read-only cluster access."
  type        = string
}

variable "hosted_zone_arns" {
  description = "Route53 hosted zone ARNs ExternalDNS may manage."
  type        = list(string)
}

variable "log_retention_days" {
  description = "Retention for control plane and flow logs."
  type        = number
  default     = 365
}

variable "deletion_protection" {
  description = "Block accidental deletion of the EKS cluster."
  type        = bool
  default     = true
}

variable "system_node_instance_types" {
  description = "Instance types for the system managed node group."
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
  default     = 2
}

variable "argocd_ha" {
  description = "Run Argo CD with two server and repo-server replicas."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "GitOps repository URL watched by Argo CD."
  type        = string
  default     = "https://github.com/adrianabelgarcia/aws-eks-platform.git"
}

variable "gitops_revision" {
  description = "Git revision the root application tracks."
  type        = string
  default     = "main"
}
