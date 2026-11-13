variable "name" {
  description = "EKS cluster name. Also used as the karpenter.sh/discovery tag value on node security groups."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}$", var.name))
    error_message = "name must be lowercase alphanumerics and hyphens, 3-39 characters, starting with a letter."
  }
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version, for example \"1.34\". Upgrades are one minor version at a time; see docs/runbooks/eks-version-upgrade.md."
  type        = string

  validation {
    condition     = can(regex("^1\\.(29|3[0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported EKS minor version in the form 1.NN, for example 1.34."
  }
}

variable "support_type" {
  description = "EKS support tier. STANDARD avoids paying for extended support by accident and forces timely upgrades."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "vpc_id" {
  description = "VPC ID that hosts the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane ENIs and managed nodes. Must span at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets."
  }
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint (CI runners, operator VPN egress). The private endpoint is always on."
  type        = list(string)

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "public_access_cidrs must contain at least one valid CIDR block."
  }

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs must not contain 0.0.0.0/0. Use the CI runner egress range or the operator VPN CIDR."
  }
}

variable "platform_admin_role_arn" {
  description = "IAM role ARN for the human platform administrators. Granted cluster admin via an access entry."
  type        = string
}

variable "terraform_role_arn" {
  description = "IAM role ARN that Terraform (CI) assumes. Terraform needs cluster admin to install Helm releases."
  type        = string
}

variable "auditor_role_arn" {
  description = "IAM role ARN granted read-only cluster access for audits and incident review."
  type        = string
}

variable "log_kms_key_arn" {
  description = "KMS key ARN for the control plane CloudWatch log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention in days for control plane logs."
  type        = number
  default     = 365
}

variable "deletion_protection" {
  description = "Block accidental cluster deletion. Enabled in prod, disabled in staging so environments can be torn down."
  type        = bool
  default     = true
}

variable "system_node_instance_types" {
  description = "Instance types for the system managed node group. Graviton (arm64) by default."
  type        = list(string)
  default     = ["m7g.large"]
}

variable "system_node_min_size" {
  description = "Minimum size of the system managed node group."
  type        = number
  default     = 2
}

variable "system_node_desired_size" {
  description = "Desired size of the system managed node group."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum size of the system managed node group."
  type        = number
  default     = 3

  validation {
    condition     = var.system_node_max_size >= 2
    error_message = "system_node_max_size must be at least 2 so the system group can span AZs."
  }
}
