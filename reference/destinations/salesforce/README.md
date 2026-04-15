# Salesforce Destination

## Overview

Salesforce is supported via the TROCCO Terraform Provider (`salesforce_output_option`).
TROCCO uses the Salesforce Bulk API for data transfer. The provider officially supports
the `salesforce_output_option` resource.

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SALESFORCE_DEST_CONNECTION_ID` | Existing TROCCO connection ID (Mode A) | `12345` |
| `SALESFORCE_DEST_USERNAME` | Salesforce login username (Mode B) | `user@example.com` |
| `SALESFORCE_DEST_PASSWORD` | Salesforce login password (Mode B) | (sensitive) |
| `SALESFORCE_DEST_SECURITY_TOKEN` | Salesforce security token (Mode B) | (sensitive) |
| `SALESFORCE_DEST_AUTH_END_POINT` | Auth endpoint (Mode B, optional) | `https://login.salesforce.com/services/Soap/u/` |
| `SALESFORCE_DEST_OBJECT_NAME` | Target object API name | `Account` |
| `SALESFORCE_DEST_ACTION_TYPE` | `insert` or `upsert` (default: `insert`) | `insert` |
| `SALESFORCE_DEST_UPSERT_KEY` | Upsert key (required when upsert) | `External_Id__c` |
| `SALESFORCE_DEST_API_VERSION` | API version (default: `55.0`) | `55.0` |

## Connection Method

### Mode A: Use Existing Connection

Set `SALESFORCE_DEST_CONNECTION_ID` to an existing TROCCO Salesforce connection ID.
No additional authentication variables are needed.

### Mode B: Create via Terraform

Leave `SALESFORCE_DEST_CONNECTION_ID` empty and provide:
- `SALESFORCE_DEST_USERNAME` + `SALESFORCE_DEST_PASSWORD` + `SALESFORCE_DEST_SECURITY_TOKEN`
- Optionally `SALESFORCE_DEST_AUTH_END_POINT` (defaults to production login endpoint)

## Terraform Configuration

### Connection

```hcl
resource "trocco_connection" "salesforce_dest" {
  count = var.salesforce_dest_connection_id == null ? 1 : 0

  name            = var.salesforce_dest_connection_name
  connection_type = "salesforce"
  description     = "Salesforce ${var.salesforce_dest_object_name} (dest) - auto-generated"

  auth_method    = "user_password"
  user_name      = var.salesforce_dest_username
  password       = var.salesforce_dest_password
  security_token = var.salesforce_dest_security_token
  auth_end_point = var.salesforce_dest_auth_end_point
}
```

### Output Option

```hcl
output_option_type = "salesforce"
output_option = {
  salesforce_output_option = {
    salesforce_connection_id = local.salesforce_dest_connection_id
    object                   = var.salesforce_dest_object_name
    action_type              = var.salesforce_dest_action_type
    api_version              = var.salesforce_dest_api_version
    ignore_nulls             = var.salesforce_dest_ignore_nulls
    throw_if_failed          = var.salesforce_dest_throw_if_failed
    upsert_key               = var.salesforce_dest_action_type == "upsert" ? var.salesforce_dest_upsert_key : null
  }
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `salesforce_connection_id` | number | Yes | TROCCO Salesforce connection ID |
| `object` | string | Yes | Target object API name |
| `action_type` | string | Yes | `insert` or `upsert` |
| `api_version` | string | No | API version (default: `55.0`) |
| `upsert_key` | string | Conditional | Upsert key (required when `action_type = "upsert"`) |
| `ignore_nulls` | bool | No | Ignore NULL values (default: `true`) |
| `throw_if_failed` | bool | No | Throw exception on error (default: `false`) |

## Action Types

| Action Type | Description |
|-------------|-------------|
| `insert` | Create new records |
| `upsert` | Update existing records by External ID, or create if not found |

## Upsert Configuration

When using `action_type = "upsert"`:

1. Set `upsert_key` to a field with the **External ID** attribute
2. Salesforce standard External ID fields or custom External ID fields can be used
3. Examples: `External_Id__c`, `Legacy_Id__c`
4. The field must have the "External ID" checkbox enabled in Salesforce Setup

If no matching record is found by the External ID, a new record is created (same as `insert`).

## REST API Fallback

If `terraform plan` fails for `salesforce_output_option`, use TROCCO REST API directly:

```bash
source .env.local
curl -s -X POST "https://trocco.io/api/job_definitions" \
  -H "Authorization: Token ${TROCCO_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{job_name}",
    "input_option_type": "{source_type}",
    "input_option": { ... },
    "output_option_type": "salesforce",
    "output_option": {
      "salesforce_connection_id": {connection_id},
      "object": "{object_name}",
      "action_type": "insert"
    },
    "filter_columns": [ ... ]
  }'
```

API docs:
- Create job definition: https://documents.trocco.io/apidocs/post-job-definition
- Salesforce destination spec: https://documents.trocco.io/docs/en/data-destination-salesforce

## Notes

- TROCCO uses Salesforce **Bulk API** for data transfer (efficient for large volumes)
- Bulk API has a limit of 10,000 batches per 24-hour rolling period
- For Sandbox environments, set `SALESFORCE_DEST_AUTH_END_POINT=https://test.salesforce.com/services/Soap/u/`
- Default API version is `55.0`; update if your org requires a specific version
- Source and destination can share the same Salesforce connection if credentials are the same (use `SALESFORCE_DEST_CONNECTION_ID` pointing to the source connection)
