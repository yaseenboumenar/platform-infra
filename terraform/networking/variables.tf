# =============================================================================
# terraform/networking/variables.tf
# =============================================================================

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dv", "te", "pp", "pd"], var.environment)
    error_message = "Must be: dv, te, pp, pd"
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
  type        = string
  description = "AWS account ID for this environment (safety check)"
}

variable "vpc_cidr" {
  type = string
  description = <<-EOT
    VPC CIDR block. Use non-overlapping ranges per account to allow future peering.
        ingest-dv:            10.0.0.0/16
        ingest-te:            10.1.0.0/16
        ingest-pp:            10.2.0.0/16
        ingest-pd:            10.3.0.0/16
        process-storage-dv:   10.10.0.0/16
        process-storage-te:   10.11.0.0/16
        process-storage-pp:   10.12.0.0/16
        process-storage-pd:   10.13.0.0/16
    EOT
}

