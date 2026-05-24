# =============================================================================
# terraform/networking/outputs.tf
#
# Consumed by pipeline repos (ingest, process-storage) via remote state:
#
#   data "terraform_remote_state" "networking" {
#     backend = "s3"
#     config  = {
#       bucket = "qbits-tfstate-ingest-dv"
#       key    = "networking/terraform.tfstate"
#       region = "eu-west-2"
#     }
#   }
#
#   subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
# =============================================================================

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_b.id
}

output "lambda_security_group_id" {
  description = "Attach this to all Lambda functions"
  value       = aws_security_group.lambda.id
}

output "glue_security_group_id" {
  description = "Attach this to all Glue jobs"
  value       = aws_security_group.glue_jobs.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
