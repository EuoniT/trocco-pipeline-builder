# Snowflake Destination

## Overview

Snowflake is supported via the TROCCO Terraform Provider (`snowflake_output_option`).
However, official examples are not available in the provider repository, so plan-time
errors may occur. A REST API fallback procedure is provided.

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SNOWFLAKE_HOST` | Account URL | `xxx.snowflakecomputing.com` |
| `SNOWFLAKE_USER` | Username | `TROCCO_USER` |
| `SNOWFLAKE_PASSWORD` | Password | (sensitive) |
| `SNOWFLAKE_WAREHOUSE` | Warehouse name | `COMPUTE_WH` |
| `SNOWFLAKE_DATABASE` | Database name | `DEMO_DB` |
| `SNOWFLAKE_SCHEMA` | Schema name | `PUBLIC` |
| `SNOWFLAKE_ROLE` | Role name | `SYSADMIN` |

## Terraform Configuration

### Connection

```hcl
resource "trocco_connection" "snowflake_dest" {
  name            = "snowflake-{db_name}"
  connection_type = "snowflake"

  host        = var.snowflake_host
  user_name   = var.snowflake_user
  auth_method = "user_password"
  password    = var.snowflake_password
  role        = var.snowflake_role
}
```

### Output Option

```hcl
output_option_type = "snowflake"
output_option = {
  snowflake_output_option = {
    snowflake_connection_id = trocco_connection.snowflake_dest.id
    warehouse               = var.snowflake_warehouse
    database                = var.snowflake_database
    schema                  = var.snowflake_schema
    table                   = var.snowflake_table
    mode                    = var.snowflake_load_mode
  }
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `snowflake_connection_id` | number | Yes | TROCCO Snowflake connection ID |
| `warehouse` | string | Yes | Snowflake warehouse |
| `database` | string | Yes | Target database |
| `schema` | string | Yes | Target schema |
| `table` | string | Yes | Target table |
| `mode` | string | No | Load mode (default: `replace`) |

### Load Modes

| Mode | Description |
|------|-------------|
| `replace` | Drop and recreate table |
| `insert` | Append records |
| `truncate_insert` | Truncate then insert |
| `merge` | Upsert (requires merge keys) |
| `insert_direct` | Direct insert (no staging) |

## REST API Fallback

If `terraform plan` fails for `snowflake_output_option`, use TROCCO REST API directly:

```bash
source .env.local
curl -s -X POST "https://trocco.io/api/job_definitions" \
  -H "Authorization: Token ${TROCCO_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{job_name}",
    "input_option_type": "kintone",
    "input_option": {
      "kintone_connection_id": {connection_id},
      "app_id": "{app_id}"
    },
    "output_option_type": "snowflake",
    "output_option": {
      "snowflake_connection_id": {connection_id},
      "warehouse": "{warehouse}",
      "database": "{database}",
      "schema": "{schema}",
      "table": "{table}",
      "mode": "replace"
    },
    "filter_columns": []
  }'
```

API docs:
- Create job definition: https://documents.trocco.io/apidocs/post-job-definition
- Snowflake destination spec: https://documents.trocco.io/docs/en/data-destination-snowflake

## Notes

- Snowflake Free Trial (30 days, $400 credits): https://signup.snowflake.com/
- Recommended initial setup: `CREATE DATABASE DEMO_DB; CREATE SCHEMA DEMO_DB.PUBLIC;`
- Use `XSMALL` warehouse with `AUTO_SUSPEND=60` for cost efficiency
- No official Terraform Provider examples exist for `snowflake_output_option` (Risk R1)
