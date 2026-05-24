# =============================================================================
# terraform/iam-oidc/variables.tf
# =============================================================================

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dv", "te", "pp", "pd"], var.environment)
    error_message = "Must be: dv, te, pp, or pd"
  }
}

variable "layer" {
  type = string
  validation {
    condition     = contains(["ingest", "process-storage"], var.layer)
    error_message = "Must be: ingest or process-storage"
  }
}

variable "account_id" {
  description = "AWS account ID for this environment"
  type        = string
}

variable "github_org" {
  description = "Your GitHub username or organisation name"
  type        = string
}