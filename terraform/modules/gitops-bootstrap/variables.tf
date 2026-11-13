variable "environment" {
  description = "Environment name. Selects gitops/clusters/<environment> as the root of the app-of-apps."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repository Argo CD watches."
  type        = string
  default     = "https://github.com/adrianabelgarcia/aws-eks-platform.git"

  validation {
    condition     = can(regex("^https://", var.gitops_repo_url))
    error_message = "gitops_repo_url must be an https:// URL."
  }
}

variable "gitops_revision" {
  description = "Git revision (branch, tag or commit) the root application tracks. Prod should track a tag or release branch once the release process exists."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.18.0"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version (used to create the root Application)."
  type        = string
  default     = "2.0.8"
}

variable "ha" {
  description = "Run Argo CD server and repo-server with two replicas. Enabled in prod."
  type        = bool
  default     = false
}
