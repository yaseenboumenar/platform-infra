# ===========================================
# terraform/organisations/outputs.tf
# ===========================================

output "ingest_dv_account_id"  { value = aws_organizations_account.ingest_dv.id }
output "ingest_te_account_id"  { value = aws_organizations_account.ingest_te.id }
output "ingest_pp_account_id"  { value = aws_organizations_account.ingest_pp.id }
output "ingest_pd_account_id"  { value = aws_organizations_account.ingest_pd.id }

output "process_dv_account_id" { value = aws_organizations_account.process_dv.id }
output "process_te_account_id" { value = aws_organizations_account.process_te.id }
output "process_pp_account_id" { value = aws_organizations_account.process_pp.id }
output "process_pd_account_id" { value = aws_organizations_account.process_pd.id }

output "lakehouse_ou_id"       { value = aws_organizations_organizational_unit.lakehouse.id }
output "ingest_ou_id"          { value = aws_organizations_organizational_unit.ingest.id }
output "process_storage_ou_id" { value = aws_organizations_organizational_unit.process_storage.id }
output "projects_ou_id"        { value = aws_organizations_organizational_unit.projects.id }
output "organization_id"       { value = aws_organizations_organization.root.id }