# Architecture Decisions

# Cost Considerations Before You Start
Since you're mimicking a corporate project solo, here's what to be careful about:

Redshift is expensive — a single-node dc2.large is ~$0.25/hr. For learning, consider Redshift Serverless (pay per query) or skip Redshift initially and just validate into S3/Delta Lake
4 AWS accounts is fine — AWS Organizations is free, and each account gets its own Free Tier
NAT Gateways are a silent cost killer (~$32/month each) — worth noting for networking later
Glue jobs charge per DPU-hour, so keep them small (2 DPUs minimum) for dev


## ADR-001: No NAT Gateway
**Status** Accepted

NAT Gateways cost ~£25/month each plus data transfer charges.
Across 8 accounts that would be £200/month minumum for nothing but routing.

Lambda and Glue only need to reach S3 and DynamoDB. Both are available via free Gateway VPC Endpoints that route traffic internally within AWS - no internet needed.
If a future service needs general internet egress, a NAT Gateway can be added then.

---

## ADR-002: GitHub OIDC instead of IAM access keys
**Status** Accepted

Storing AWS access keys as GitHub secrets is a security risk — keys can leak,
don't auto-rotate, and are hard to audit. OIDC lets GitHub Actions exchange a
short-lived JWT token for temporary AWS credentials. Nothing stored. Nothing to rotate.
Credentials expire automatically after each workflow run.

---

## ADR-003: One AWS account per layer per environment
**Status:** Accepted

Mirrors enterprise practice. Blast radius isolation means a misconfigured IAM
policy in ingest-dv can never touch process-storage-pd. Billing splits cleanly
by layer. SCPs can enforce different rules per layer (e.g. ingest accounts
can never create Redshift — it's architecturally wrong for that layer).

---

## ADR-004: Separate TF state per account
**Status:** Accepted

Each account has its own S3 state bucket and DynamoDB lock table. This means
a failed apply in one account never blocks another. State is isolated by the
same boundary as the account itself.

---

## ADR-005: process-storage naming (not process)
**Status:** Accepted

Accounts are named `qbits-process-storage-{env}` to match the naming convention
visible in the reference organisation (lakehouse-process-storage-dv etc.).
This makes it immediately clear which architectural layer an account belongs to
when viewing the full account list.