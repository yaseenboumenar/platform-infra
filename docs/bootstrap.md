# Bootstrap Guide

These steps must be done **manually** before any terraform or github actions can be run.
Do these once in order.

---

## Step 1: Create root account TF state bucket and lock table

Log into your `qbits` management account (YOUR_MANAGEMENT_ACCOUNT_ID).

**Create S3 bucket:**
- Name: `qbits-tfstate-root`
- Region: `eu-west-2`
- Block all public access: ✅
- Versioning: ✅ (allows recovery from bad applies)
- Encryption: SSE-S3 (free)

**Create DynamoDB table:**
- Name: `qbits-tflock-root`
- Partition Key: `LockID` (type: String)
- Billing: On-demand (near-zero cost for TF locks)

---

## Step 2: Import existing accounts and apply the organisations module

8 accounts have been created so far manually in AWS.
Terraform doesn't know about them yet - we need to import them first.

```bash
cd terraform/organisations
cp terraform.tfvars.example terraform.tfvars
# Fill in your root account ID and email addresses
# terraform.tfvars is gitignored - never commit it

# terraform init
terraform init -backend-config="bucket=qbits-tfstate-root" -backend-config="key=organizations/terraform.tfstate" -backend-config="region=eu-west-2" -backend-config="dynamodb_table=qbits-tflock-root" -reconfigure

# Import all 8 existing accounts into Terraform state
terraform import aws_organizations_account.ingest_dv    YOUR_INGEST_DV_ACCOUNT_ID
terraform import aws_organizations_account.ingest_te    YOUR_INGEST_TE_ACCOUNT_ID
terraform import aws_organizations_account.ingest_pp    YOUR_INGEST_PP_ACCOUNT_ID
terraform import aws_organizations_account.ingest_pd    YOUR_INGEST_PD_ACCOUNT_ID
terraform import aws_organizations_account.process_dv   YOUR_PROCESS_DV_ACCOUNT_ID
terraform import aws_organizations_account.process_te   YOUR_PROCESS_TE_ACCOUNT_ID
terraform import aws_organizations_account.process_pp   YOUR_PROCESS_PP_ACCOUNT_ID
terraform import aws_organizations_account.process_pd   YOUR_PROCESS_PD_ACCOUNT_ID

# Now plan - review what will be created (OUs, SCPs)
terraform plan

# Apply - create OUs, moves accounts into them, applies SCPs
terraform apply

# The safer pattern is:
# Save the plan to a file
terraform plan -out=tfplan

# Apply exactly that saved plan — no re-evaluation
terraform apply tfplan

# When you use -out, Terraform locks the plan. The apply executes precisely what the plan described — no surprises.
# Something in AWS could theoretically changing — another process, another engineer, a manual console change... won't effect us!

```

This creates 8 child accounts across Ingest and Process-Storage OUs.
**Note all 8 account IDs from the output.**

---

## Step 3: Create TF state buckets in each child account

Each of the 8 accounts needs its own S3 bucket and DynamoDB table.
Naming convetion: `qbits-tfstate-{layer}-{env}` / `qbits-tflock-{layer}-{env}`

| Account                    | S3 Bucket                     | DynamoDB Table                |
|----------------------------|-------------------------------|-------------------------------|
| qbits-ingest-dv            | qbits-tfstate-ingest-dv       | qbits-tflock-ingest-dv        |
| qbits-ingest-te            | qbits-tfstate-ingest-te       | qbits-tflock-ingest-te        |
| qbits-ingest-pp            | qbits-tfstate-ingest-pp       | qbits-tflock-ingest-pp        |
| qbits-ingest-pd            | qbits-tfstate-ingest-pd       | qbits-tflock-ingest-pd        |
| qbits-process-storage-dv   | qbits-tfstate-ingest-dv       | qbits-tflock-ingest-dv        |
| qbits-process-storage-te   | qbits-tfstate-ingest-te       | qbits-tflock-ingest-te        |
| qbits-process-storage-pp   | qbits-tfstate-ingest-pp       | qbits-tflock-ingest-pp        |
| qbits-process-storage-pd   | qbits-tfstate-ingest-pd       | qbits-tflock-ingest-pd        |

Use the AWS CLI with assumed role (repeat for each account):

```bash
CHILD_ACCOUNT=<account id>
LAYER=ingest    # or process
ENV=dv          # or te, pp, pd
REGION=eu-west-2

# Go into any child account from the management account
creds=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${CHILD_ACCOUNT}:role/OrganisationAccountAccessRole" \
  --role-session-name "bootstrap-${LAYER}-${ENV}" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo $creds | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY_ID=$(echo $creds | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $creds | awk '{print $3}')

# S3 bucket
aws s3api create-bucket \
  --bucket qbits-tfstate-${LAYER}-${ENV} \
  --region $REGION
  --create-bucket-configuration LocationConstraint=$REGION

aws s3api put-bucket-versioning \
  --bucket qbits-tfstate-${LAYER}-${ENV} \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket qbits-tfstate-${LAYER}-${ENV} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# DynamoDB
aws dynamondb create-table \
  --table-name qbits-tflock-${LAYER}-${ENV} \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION

PS C:\Users\blade\OneDrive\Desktop\platform-infra\terraform\organisations> # ── Change these three values each run ──────────────────
>> $CHILD_ACCOUNT = "12 digit id"     # account ID
>> $LAYER         = ""                # ingest or process-storage
>> $ENV           = ""                # dv, te, pp, or pd
>> # ────────────────────────────────────────────────────────
>> 
>> # Assume into the child account
>> $creds = aws sts assume-role `
>>   --role-arn "arn:aws:iam::${CHILD_ACCOUNT}:role/OrganizationAccountAccessRole" `
>>   --role-session-name "bootstrap-${LAYER}-${ENV}" `
>>   --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" `
>>   --output text
>> 
>> $parts = $creds -split "\s+"
>> $env:AWS_ACCESS_KEY_ID     = $parts[0]
>> $env:AWS_SECRET_ACCESS_KEY = $parts[1]
>> $env:AWS_SESSION_TOKEN     = $parts[2]
>> 
>> # Verify you're now in the child account
>> aws sts get-caller-identity
>> 
>> # Create S3 state bucket
>> aws s3api create-bucket `
>>   --bucket "qbits-tfstate-${LAYER}-${ENV}" `
>>   --region eu-west-2 `
>>   --create-bucket-configuration LocationConstraint=eu-west-2
>> 
>> aws s3api put-bucket-versioning `
>>   --bucket "qbits-tfstate-${LAYER}-${ENV}" `
>>   --versioning-configuration Status=Enabled
>> 
>> aws s3api put-public-access-block `
>>   --bucket "qbits-tfstate-${LAYER}-${ENV}" `
>>   --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
>> 
>> # Create DynamoDB lock table
>> aws dynamodb create-table `
>>   --table-name "qbits-tflock-${LAYER}-${ENV}" `
>>   --attribute-definitions AttributeName=LockID,AttributeType=S `
>>   --key-schema AttributeName=LockID,KeyType=HASH `
>>   --billing-mode PAY_PER_REQUEST `
>>   --region eu-west-2
>> 
>> # Clear credentials before next account build
>> Remove-Item Env:AWS_ACCESS_KEY_ID
>> Remove-Item Env:AWS_SECRET_ACCESS_KEY
>> Remove-Item Env:AWS_SESSION_TOKEN
>>
>> # Write note: 
>> Write-Host "Done: qbits-tfstate-${LAYER}-${ENV}"
```

---

## Step 4: Apply OIDC module to each child account

This creates the GitHub Actions trust in each account so workflows can deploy without stored credentials.

```bash
cd terraform/iam-oidc

# Repeat for each 8 accounts - example for ingest-dv:
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

# ── Change these three values each run ──────────────────
$CHILD_ACCOUNT = "865679935699"
$LAYER         = "process-storage"
$ENV           = "pd"
$GITHUB_ORG    = "yaseenboumenar"
# ────────────────────────────────────────────────────────

$creds = aws sts assume-role `
  --role-arn "arn:aws:iam::${CHILD_ACCOUNT}:role/OrganizationAccountAccessRole" `
  --role-session-name "oidc-${LAYER}-${ENV}" `
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" `
  --output text

$parts = $creds -split "\s+"
$env:AWS_ACCESS_KEY_ID     = $parts[0]
$env:AWS_SECRET_ACCESS_KEY = $parts[1]
$env:AWS_SESSION_TOKEN     = $parts[2]

# Verify correct account
aws sts get-caller-identity

# Navigate to iam-oidc module
cd C:\Users\blade\OneDrive\Desktop\platform-infra\terraform\iam-oidc

# Initialise with this account's state bucket
terraform init `
  -backend-config="bucket=qbits-tfstate-${LAYER}-${ENV}" `
  -backend-config="key=iam-oidc/terraform.tfstate" `
  -backend-config="region=eu-west-2" `
  -backend-config="dynamodb_table=qbits-tflock-${LAYER}-${ENV}" `
  -reconfigure

# Apply
terraform apply `
  -var="environment=${ENV}" `
  -var="layer=${LAYER}" `
  -var="account_id=${CHILD_ACCOUNT}" `
  -var="github_org=${GITHUB_ORG}" `
  -auto-approve

# Clear credentials
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

Write-Host "OIDC done: ${LAYER}-${ENV}"
```

---

## Step 5: Add GitHub Secrets

In `platform-infra` GitHub repo → Settings → Secrets and Variables → Actions:

| Secret                  | Value                            |
|-------------------------|----------------------------------|
| INGEST_DV_ACCOUNT_ID    | (qbits-ingest-dv ID)             |
| INGEST_TE_ACCOUNT_ID    | (qbits-ingest-te ID)             |
| INGEST_PP_ACCOUNT_ID    | (qbits-ingest-pp ID)             |
| INGEST_PD_ACCOUNT_ID    | (qbits-ingest-pd ID)             |
| PROCESS_DV_ACCOUNT_ID   | (qbits-process-storage-dv ID)    |
| PROCESS_TE_ACCOUNT_ID   | (qbits-process-storage-te ID)    |
| PROCESS_PP_ACCOUNT_ID   | (qbits-process-storage-pp ID)    |
| PROCESS_PD_ACCOUNT_ID   | (qbits-process-storage-pd ID)    |

---

## Step 6: Push to GitHub and test

```bash
git init
git remote and origin
git add .
git commit -m "feature/102: initial platform-infra setup"
git push -u origin main
```

Pushing to main will automatically trigger the `deploy-networking` workflow
for both ingest-dv and process-storage-dv. Check the Actions tab in GitHub.

---

## What you now have after all steps are complete

```
AWS Organizations
└── Root (qbits - 471112627120)
    ├── Lakehouse OU
    │   ├── Ingest OU
    │   │   ├── qbits-ingest-dv   (VPC 10.0.0.0/16)
    │   │   ├── qbits-ingest-te   (VPC 10.1.0.0/16)
    │   │   ├── qbits-ingest-pp   (VPC 10.2.0.0/16)
    │   │   └── qbits-ingest-pd   (VPC 10.3.0.0/16)
    │   └── Process-Storage OU
    │       ├── qbits-process-storage-dv  (VPC 10.10.0.0/16)
    │       ├── qbits-process-storage-te  (VPC 10.11.0.0/16)
    │       ├── qbits-process-storage-pp  (VPC 10.12.0.0/16)
    │       └── qbits-process-storage-pd  (VPC 10.13.0.0/16)
    └── Projects OU               (empty — ready for verint)

✅ GitHub Actions, keyless deploy to any account via OIDC (i.e. without needing stored credentials)
✅ Terraform state stored safely in S3 per account
✅ All accounts locked to eu-west-2 via SCP
✅ Ingest accounts blocked from creating Redshift (wrong layer)

Next: build do-aws-lakehouse-ingest repo
```