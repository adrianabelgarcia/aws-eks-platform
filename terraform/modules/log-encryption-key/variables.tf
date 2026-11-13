variable "name" {
  description = "Prefix used for the KMS key alias and description. Usually the environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name))
    error_message = "name must be lowercase alphanumerics and hyphens, 3-41 characters, starting with a letter."
  }
}
