variable "name" {
  description = "Name prefix for the VPC and its child resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name))
    error_message = "name must be lowercase alphanumerics and hyphens, 3-41 characters, starting with a letter."
  }
}

variable "cluster_name" {
  description = "EKS cluster name. Used for the karpenter.sh/discovery subnet tag so Karpenter can find private subnets."
  type        = string
}

variable "cidr" {
  description = "IPv4 CIDR block for the VPC. Must be a /16 so the module's subnet math (/20 private, /24 public) holds."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) == 16
    error_message = "cidr must be a valid IPv4 /16 block, for example 10.10.0.0/16."
  }
}

variable "availability_zones" {
  description = "Availability zone names to span, for example [\"us-east-1a\", \"us-east-1b\", \"us-east-1c\"]. Pinned explicitly so the subnet layout never changes when AWS adds a zone. Zone names map to different physical zones per account, so pick names that exist in the target account."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "availability_zones must list 2 or 3 zones."
  }

  validation {
    condition     = alltrue([for az in var.availability_zones : can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9][a-z]$", az))])
    error_message = "Each entry must be an AZ name such as us-east-1a."
  }
}

variable "nat_strategy" {
  description = "NAT topology. 'single' places one NAT gateway (cheap, a zonal failure takes out egress). 'per_az' places one per AZ (resilient, higher fixed cost)."
  type        = string

  validation {
    condition     = contains(["single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be either 'single' or 'per_az'."
  }
}

variable "log_kms_key_arn" {
  description = "KMS key ARN used to encrypt the VPC flow log CloudWatch log group."
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention in days for VPC flow logs. Minimum 365 to satisfy the audit baseline."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a value CloudWatch Logs accepts, for example 365."
  }
}
