# =============================================================================
# terraform/iam-oidc/main.terraform
#
# PURPOSE: GitHub Actions OIDC trust for one account.
# Applied once per account (8 times total).
#
# HOW OIDC WORK:
#   1. GitHub Actions workflow runs and requests a signed JWT token from GitHub
#   2. Workflow calls sts:AssumeRoleWithWebIdentity, passing the JWT
#   3. AWS verifies the JWT signature against GitHub's policy OIDC keys
#   4. AWS checks the role's trust policy conditions (repo name, branch etc.)
#   5. AWS returns temporary credentials valid for 1 hour
#   6. Workflow uses those credentials - they expire automatically
#
#   Result: No stored credentials anywhere. Nothing to rotate. Nothing to leak.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
    region              = var.aws_region
    allowed_account_ids = [var.account_id]
}

# =============================================================================
# Register GitHubas OIDC Identity Provider
#
# This is a one-time registeration per account telling AWS:
# "I trust JWT tokens signed by token.actions.githubusercontent.com"
#
# The thumbprint is GitHub's TLS certificate fingerprint - AWS uses it to
# verify it's talking to the real GitHub OIDC endpoint.
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    name        = "github-oidc-provider"
    environment = var.environment
    layer       = var.layer
    managedby   = "terraform"
  }
}

# =============================================================================
# IAM Role - Platform repo (platform-infra)
#
# Used by this repo's own workflows to deploy networking, OIDC etc.
# Trust policy restricts to your GitHub org/username, platform-infra repo only.
# =============================================================================

resource "aws_iam_role" "github_actions_platform" {
  name        = "github-actions-platform-${var.environment}"
  description = "Assumed by platform-infra GitHub Actions workflows"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
            StringEquals = {
                "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            }
            StringLike = {
                # Only tokens from YOUR platform-infra repo can assume this role
                "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/platform-infra:*"
            }
        }
    }]
  })

  tags = { Name = "github-actions-platform-${var.environment}", ManagedBy = "terraform" }
}

resource "aws_iam_role_policy_attachment" "platform_poweruser" {
  role       = aws_iam_role.github_actions_platform.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "platform_iam" {
  name = "platform-iam-permissions"
  role = aws_iam_role.github_actions_platform.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRole", "iam:GetRolePolicy",
        "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:PassRole",
        "iam:TagRole", "iam:UntagRole", "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider"
      ]
      Resource = "*"
    }]
  })
}


# =============================================================================
# IAM Role — Data pipeline repos (ingest, process-storage)
#
# Used by the do-aws-lakehouse-* repos to deploy S3, Glue, Lambda etc.
# Scoped to only what data pipeline deployment needs.
# Trust policy allows any repo in your org starting with "do-aws-lakehouse-"
# =============================================================================

resource "aws_iam_role" "github_actions_data" {
  name        = "github-actions-data-${var.environment}"
  description = "Assumed by data pipeline repo GitHub Actions workflows"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Any do-aws-lakehouse-* repo in your org can assume this role
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/do-aws-lakehouse-*:*"
        }
      }
    }]
  })

  tags = { Name = "github-actions-data-${var.environment}", ManagedBy = "terraform" }
}

resource "aws_iam_role_policy" "data_pipeline_permissions" {
  name = "data-pipeline-deploy-permissions"
  role = aws_iam_role.github_actions_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Management"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = [
          "arn:aws:s3:::qbits-*-${var.environment}",
          "arn:aws:s3:::qbits-*-${var.environment}/*"
        ]
      },
      {
        Sid      = "GlueManagement"
        Effect   = "Allow"
        Action   = ["glue:*"]
        Resource = "*"
      },
      {
        Sid      = "LambdaManagement"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:*"
      },
      {
        Sid      = "SQSManagement"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:*"
      },
      {
        Sid      = "IAMForDataRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy",
                    "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
                    "iam:GetRole", "iam:GetRolePolicy", "iam:PassRole", "iam:TagRole"]
        Resource = "arn:aws:iam::${var.account_id}:role/data-*"
      },
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::qbits-tfstate-${var.layer}-${var.environment}",
          "arn:aws:s3:::qbits-tfstate-${var.layer}-${var.environment}/*"
        ]
      },
      {
        Sid      = "TerraformLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem",
                    "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/qbits-tflock-${var.layer}-${var.environment}"
      }
    ]
  })
}
