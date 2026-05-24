# =============================================================================
# terraform/organizations/variables.tf
# =============================================================================

variable "aws_region" {
    type    = string
    default = "eu-west-2"
}

variable "root_account_id" {
    description = "Management account ID - safety check to prevent applying to wrong account"
    type        = string
}

variable "account_emails" {
    description = <<-EOT
      Unique email per child account. Uses Gmail + aliases so all land in one inbox.
      Keys: ingest_dv, ingest_te, ingest_pp, ingest_pd,
            process_dv, process_te, process_pp, process_pd
    EOT
    type        = map(string)
}