# =============================================================================
# terraform/networking/main.tf
#
# PURPOSE: Baseline VPC for one account/environment
# Applied once per account (8 times total) via GitHub Actions.
#
# WHAT IT CREATES:
#   - VPC with DNS enabled
#   - 2 private subnets across 2 AZs (eu-west-2a, eu-west-2b)
#   - Route tables (no internet gateway, no NAT - by design)
#   - s3 Gateway Endpoint (free - route s3 traffic internall)
#   - DynamoDB Gateway Endpoint (free - routes DynamoDB traffic internally)
#   - Glue Interface Endpoint (allows Glue jobs to call Glue API privately)
#   - Security groups for Lambda and Glue jobs
#   - VPC flow logs (traffic metadata for debugging)
#
# NETWORKING CONCEPTS:
#   VPC             Your isolated private network in AWS
#   Subnet          A slice of the VPC tied to one availability zone
#   Route Table     Rules for where traffic goes (like a post office sorting table)
#   Gateway EP      Free route that keeps S3/DynamoDB traffic inside AWS
#   Interface EP    A real network card in your subnet for calling AWS APIs
#   Security Group  Stateful firewall attached to a resource
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }

  # Backend values injected at runtime by GitHub Actions workflow:
  # terraform init \
  #   -backend-config="bucket=qbits-tfstate-ingest-dv"
  #   -backend-config="key=networking/terraform.tfstate" \
  #   -backend-config="region=eu-west-2" \
  #   -backend-config="dynamodb_table=qbits-tflock-ingest-dv"
  backend "s3" {}
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repository = "platform-infra"
      Layer = var.layer
      Environment = var.environment
    }
  }
}

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block            = var.vpc_cidr
  enable_dns_hostnames  = true
  enable_dns_support    = true
  tags                  = { name = "vpc-${var.layer}-${var.environment}" }
}

# =============================================================================
# Private Subnets - 2 AZs for resilience
#
# cidrsubnet(var.vpc_cidr, 8, N) carves a /24 from the /16
# e.g. 10.0.0.0/16 -> 10.0.1.0/24 (AZ-a) and 10.0.2.0/24 (AZ-b)
# =============================================================================

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = "${var.aws_region}a"
  tags              = { name = "subnet-private-${var.layer}-${var.environment}-a"}
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = "${var.aws_region}b"
  tags = { Name = "subnet-private-${var.layer}-${var.environment}-b" }
}


# =============================================================================
# Route Tables
#
# No route to internet gateway or NAT — nothing in these subnets can reach
# the public internet. S3/DynamoDB traffic routes via Gateway Endpoints below.
# =============================================================================

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "rt-private-${var.layer}-${var.environment}-a" }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "rt-private-${var.layer}-${var.environment}-b" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

# =============================================================================
# Gateway VPC Endpoints — S3 and DynamoDB (FREE)
#
# Without these, Lambda/Glue in private subnets cannot reach S3 at all
# (no internet, no NAT). With these, traffic routes internally within AWS
# at no cost. You'll see them appear as entries in the route table.
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]
  tags = { Name = "vpce-s3-${var.layer}-${var.environment}" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]
  tags = { Name = "vpce-dynamodb-${var.layer}-${var.environment}" }
}

# =============================================================================
# Interface VPC Endpoint — Glue (~£7/month)
#
# Unlike Gateway Endpoints, Interface Endpoints are actual ENIs (network cards)
# in your subnet. Needed so Glue jobs running inside the VPC can call the
# Glue API (get job details, update run status etc.) without internet access.
# =============================================================================

resource "aws_security_group" "vpce_glue" {
  name        = "vpce-glue-${var.layer}-${var.environment}"
  description = "Controls access to the Glue Interface VPC Endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from Glue jobs"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.glue_jobs.id]
  }

  tags = { Name = "vpce-glue-sg-${var.layer}-${var.environment}" }
}

resource "aws_vpc_endpoint" "glue" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.glue"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_glue.id]
  tags = { Name = "vpce-glue-${var.layer}-${var.environment}" }
}

# =============================================================================
# Security Groups
#
# Defined here in the platform layer so data pipeline repos can reference
# them by ID without managing their own security groups (which leads to sprawl).
#
# Lambda SG: no ingress (Lambda is invoked by AWS services, not network calls)
# Glue SG:   self-referencing ingress (Glue driver/worker internal comms)
# =============================================================================

resource "aws_security_group" "lambda" {
  name        = "lambda-${var.layer}-${var.environment}"
  description = "Attached to Lambda functions in the data platform"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # Note: no NAT/IGW means this can only actually reach VPC endpoints
  }

  tags = { Name = "sg-lambda-${var.layer}-${var.environment}" }
}

resource "aws_security_group" "glue_jobs" {
  name        = "glue-jobs-${var.layer}-${var.environment}"
  description = "Attached to Glue ETL jobs"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Glue internal driver-to-worker communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true  # allows traffic from other resources in this same SG
  }

  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-glue-${var.layer}-${var.environment}" }
}

# =============================================================================
# VPC Flow Logs — traffic metadata for debugging network issues
# Captures: source IP, dest IP, port, accept/reject. NOT actual data content.
# =============================================================================

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.layer}-${var.environment}"
  retention_in_days = 7
}

resource "aws_iam_role" "flow_logs" {
  name = "vpc-flow-logs-${var.layer}-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
                  "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
}
