# =============================================================================
# terraform/iam-oidc/outputs.tf
# =============================================================================

output "platform_role_arn" {
  description = "Role ARN for platform-infra workflows"
  value       = aws_iam_role.github_actions_platform.arn
}

output "data_role_arn" {
  description = "Role ARN for data pipeline workflows"
  value       = aws_iam_role.github_actions_data.arn
}

output "oidc_provider_arn" {
    description = "GitHub OIDC provider ARN"
    value       = aws_iam_openid_connect_provider.github.arn
}


# A good rule of thumb for outputs: only output what something outside this module needs to consume.
# Policies, security group rules, route table associations — these are all internal wiring.
# The ARNs of roles, VPC IDs, subnet IDs — these are the handles other things grab onto.
