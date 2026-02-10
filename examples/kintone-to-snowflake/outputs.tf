output "job_definition_id" {
  description = "Created TROCCO job definition ID"
  value       = trocco_job_definition.kintone_to_snowflake.id
}

output "kintone_connection_id" {
  description = "kintone connection ID (existing or newly created)"
  value       = local.kintone_connection_id
}

output "snowflake_connection_id" {
  description = "Snowflake connection ID (existing or newly created)"
  value       = local.snowflake_connection_id
}

output "job_name" {
  description = "Job definition name"
  value       = trocco_job_definition.kintone_to_snowflake.name
}

output "pipeline_summary" {
  description = "Pipeline summary"
  value = {
    source      = "kintone (app_id: ${var.kintone_app_id})"
    destination = "snowflake (${var.snowflake_database}.${var.snowflake_schema}.${var.snowflake_table})"
    columns     = length(var.filter_columns)
  }
}
