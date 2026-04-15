output "job_definition_id" {
  description = "Created TROCCO job definition ID"
  value       = trocco_job_definition.snowflake_to_salesforce.id
}

output "snowflake_src_connection_id" {
  description = "Snowflake source connection ID (existing or newly created)"
  value       = local.snowflake_src_connection_id
}

output "salesforce_dest_connection_id" {
  description = "Salesforce destination connection ID (existing or newly created)"
  value       = local.salesforce_dest_connection_id
}

output "job_name" {
  description = "Job definition name"
  value       = trocco_job_definition.snowflake_to_salesforce.name
}

output "pipeline_summary" {
  description = "Pipeline summary"
  value = {
    source      = "snowflake (${var.snowflake_src_database}.${var.snowflake_src_schema})"
    destination = "salesforce (object: ${var.salesforce_dest_object_name})"
    columns     = length(var.filter_columns)
  }
}
