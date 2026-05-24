# ================================================================================================
# terraform/organisations/main.tf
#
# PURPOSE: AWS organisations structure - OUs, account placement and SCPs.
#
# WHO RUNS THIS: The DE (i.e. me), manually, once, from the management account.
# HOW: cd terraform/organisations && terraform init && terraform import ... && terraform apply
#
# NOTE: The 8 child accounts already exist (created manually in console).
#       Run terraform import for each before terraform apply.
#       See docs/bootstrap.md - step 2 for the exact import commands.
# ================================================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }

  # State lives in the root management account s3 bucket.
  # Create this bucket manually before running terraform init (see bootstrap.md - step 1)
  backend "s3" {
    bucket = "qbits-tfstate-root"
    key = "organisations/terraform.tfstate"
    region = "eu-west-2"
    dynamodb_table = "qbits-tflock-root"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
  # Safety check - fails if you run it in child account
  allowed_account_ids = [var.root_account_id]
}

# =============================================================================
# Enable AWS organisations
# ALL_FEATURE enables SCPs - the guardrails that restrict what child accounts
# can do (even if their own IAM policies allow it)
# =============================================================================

resource "aws_organizations_organization" "root" {
  feature_set = "ALL"   # enables SCPs — AWS calls this "ALL_FEATURES"
                        # Terraform provider uses shorthand "ALL"

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com"
  ]

  # Tell Terraform SCPs should be enabled
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY"
  ]
}

# =============================================================================
# Organisational Units (OUs)
#
# OUs are folders. Attaching an SCP to an OU applies it to every account,
# including accounts in nested OUs.
#
# Structure:
#   Root
#   ├── Lakehouse OU
#   │   ├── Ingest OU           ← qbits-ingest-dv/te/pp/pd
#   │   └── Process-Storage OU  ← qbits-process-storage-dv/te/pp/pd
#   └── Projects OU             ← qbits-verint-np etc. (added later)
# =============================================================================

resource "aws_organizations_organizational_unit" "lakehouse" {
  name      = "Lakehouse"
  parent_id = aws_organizations_organization.root.roots[0].id
}

resource "aws_organizations_organizational_unit" "ingest" {
  name      = "Ingest"
  parent_id = aws_organizations_organizational_unit.lakehouse.id
}

resource "aws_organizations_organizational_unit" "process_storage" {
  name      = "ProcessStorage"
  parent_id = aws_organizations_organizational_unit.lakehouse.id
}

resource "aws_organizations_organizational_unit" "projects" {
  name      = "Projects"
  parent_id = aws_organizations_organization.root.roots[0].id
}

# =============================================================================
# Child accounts
#
# These already exist - they were created manually in the AWS console.
# Use terraform import to bring them under Terraform management.
# See docs/bootstrap.md for exact import commands.
#
# prevent_history = true means Terraform will refuse to delete these even if
# you remove them from config. Account closure is a 90-day manual process.
# =============================================================================

# --- Ingest accounts --- #

resource "aws_organizations_account" "ingest_dv" {
  name      = "qbits-ingest-dv"
  email     = var.account_emails["ingest_dv"]
  parent_id = aws_organizations_organizational_unit.ingest.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "ingest", Environment = "dv" })
}

resource "aws_organizations_account" "ingest_te" {
  name      = "qbits-ingest-te"
  email     = var.account_emails["ingest_te"]
  parent_id = aws_organizations_organizational_unit.ingest.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "ingest", Environment = "te" })
}

resource "aws_organizations_account" "ingest_pp" {
  name      = "qbits-ingest-pp"
  email     = var.account_emails["ingest_pp"]
  parent_id = aws_organizations_organizational_unit.ingest.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "ingest", Environment = "pp" })
}

resource "aws_organizations_account" "ingest_pd" {
  name      = "qbits-ingest-pd"
  email     = var.account_emails["ingest_pd"]
  parent_id = aws_organizations_organizational_unit.ingest.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "ingest", Environment = "pd" })
}

# --- Process Storage accounts ---

resource "aws_organizations_account" "process_dv" {
  name      = "qbits-process-storage-dv"
  email     = var.account_emails["process_dv"]
  parent_id = aws_organizations_organizational_unit.process_storage.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "process-storage", Environment = "dv" })
}

resource "aws_organizations_account" "process_te" {
  name      = "qbits-process-storage-te"
  email     = var.account_emails["process_te"]
  parent_id = aws_organizations_organizational_unit.process_storage.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "process-storage", Environment = "te" })
}

resource "aws_organizations_account" "process_pp" {
  name      = "qbits-process-storage-pp"
  email     = var.account_emails["process_pp"]
  parent_id = aws_organizations_organizational_unit.process_storage.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "process-storage", Environment = "pp" })
}

resource "aws_organizations_account" "process_pd" {
  name      = "qbits-process-storage-pd"
  email     = var.account_emails["process_pd"]
  parent_id = aws_organizations_organizational_unit.process_storage.id
 # role_name = "OrganizationAccountAccessRole" 
  lifecycle { prevent_destroy = true }
  tags = merge(local.common_tags, { Layer = "process-storage", Environment = "pd" })
}

# =============================================================================
# Service Control Policies (SCPs)
#
# SCPs are the outer fence - they restrict what IAM can ever allow in an account,
# even for that account's own root user. Both SCP and IAM must allow an action
# for it to succeed.
#
# SCP 1: Lock all accounts to eu-west-2 (applie to entire Lakehouse OU)
# SCP 2: Block Redshift entirely in Ingest OU (would cost £180/month in the ingest account doing nothing)
# SCP 3: Block provisioned Redshift in Process-Storage dv/te (use serverless there to save £)
# =============================================================================

# --- SCP 1: Region lockdown --- #

resource "aws_organizations_policy" "deny_non_london" {
  name        = "DenyNonLondonRegions"
  description = "Prevent any resource creation outside eu-west-2"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyAllOutsideLondon"
      Effect = "Deny"
      # NotAction = deny everything EXCEPT these global services which have no region
      NotAction = [
        "iam:*", "organizations:*", "route53:*", "budgets:*",
        "waf:*", "cloudfront:*", "sts:*", "support:*", "trustedadvisor:*"
      ]
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = "eu-west-2" }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_non_london_lakehouse" {
  policy_id = aws_organizations_policy.deny_non_london.id
  target_id = aws_organizations_organizational_unit.lakehouse.id
}

# --- SCP 2: Block all Redshift in Ingest OU --- #

resource "aws_organizations_policy" "deny_redshift_ingest" {
  name        = "DenyRedshiftInIngest"
  description = "Ingest layer should never have Redshift — architecturally wrong layer"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyAllRedshift"
      Effect   = "Deny"
      Action   = ["redshift:*", "redshift-serverless:*"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_redshift_ingest" {
  policy_id = aws_organizations_policy.deny_redshift_ingest.id
  target_id = aws_organizations_organizational_unit.ingest.id
}

# --- SCP 3: Block provisioned Redshift in process-storage dv and te --- #

resource "aws_organizations_policy" "deny_redshift_provisioned_nonprod" {
  name        = "DenyProvisionedRedshiftNonProd"
  description = "Use Redshift Serverless in dv/te — provisioned clusters too expensive for non-prod"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRedshiftClusterCreate"
      Effect   = "Deny"
      Action   = ["redshift:CreateCluster"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_redshift_process_dv" {
  policy_id = aws_organizations_policy.deny_redshift_provisioned_nonprod.id
  target_id = aws_organizations_account.process_dv.id
}

resource "aws_organizations_policy_attachment" "deny_redshift_process_te" {
  policy_id = aws_organizations_policy.deny_redshift_provisioned_nonprod.id
  target_id = aws_organizations_account.process_te.id
}

# =============================================================================
# Shared tags applied to all resources in this module
# =============================================================================

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Repository = "platform-infra"
    Owner      = "qbits"
  }
}