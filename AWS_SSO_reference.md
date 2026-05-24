
## AWS SSO reference for work ##

When you join a company that uses AWS SSO, the setup looks like this:

# Step 1 — one time setup, configure the SSO profile
aws configure sso

# It asks you:
SSO session name: qbits-dev                         # you choose a name
SSO start URL: https://qbits.awsapps.com/start      # company provides this
SSO region: eu-west-2
SSO registration scopes: sso:account:access

# Browser opens automatically → you log in with company credentials
# (usually your Google/Microsoft work account)

# Then it asks:
CLI default client Region: eu-west-2
CLI default output format: json
CLI profile name: qbits-ingest-dv                   # name for this account/role combo
After that, switching between accounts is just:

# Authenticate (opens browser, lasts 8 hours)
aws sso login --profile qbits-ingest-dv

# Use a specific account
aws s3 ls --profile qbits-ingest-dv
aws sts get-caller-identity --profile qbits-ingest-dv

# Set a default profile for your terminal session
# so you don't have to type --profile every time
export AWS_PROFILE=qbits-ingest-dv   # Mac/Linux
$env:AWS_PROFILE="qbits-ingest-dv"   # Windows PowerShell
In a multi-account setup at work you'd have a profile per account:
~/.aws/config

[profile qbits-ingest-dv]
sso_session = qbits
sso_account_id = 639163294469
sso_role_name = DataEngineerAccess
region = eu-west-2

[profile qbits-process-dv]
sso_session = qbits
sso_account_id = 809868872120
sso_role_name = DataEngineerAccess
region = eu-west-2

[sso-session qbits]
sso_start_url = https://qbits.awsapps.com/start
sso_region = eu-west-2
sso_registration_scopes = sso:account:access
Then Terraform uses it like this:
hclprovider "aws" {
  region  = "eu-west-2"
  profile = "qbits-ingest-dv"    # matches the profile name above
}

# The key differences from our current setup
Current (IAM user + access keys)    Work (SSO)
────────────────────────────────────────────────
Keys stored in ~/.aws/credentials   No keys stored anywhere
Never expire                        Expire after 8 hours
One set of keys for everything      Separate profile per account
Security risk if leaked             Useless if intercepted — expired
Manual rotation required            Auto-rotated every session
