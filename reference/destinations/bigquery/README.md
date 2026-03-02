# BigQuery Destination

## Overview

BigQuery is the recommended destination for Phase 1. The TROCCO Terraform Provider has
full support with official examples for `bigquery_output_option`.

## Required Setup

### 1. BigQuery Connection in TROCCO

BigQuery connections in TROCCO use OAuth or service account authentication.
**Create the connection via TROCCO UI first**, then reference it by ID in Terraform.

TROCCO UI: Settings > Connections > New > BigQuery

### 2. Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `BQ_CONNECTION_ID` | TROCCO BigQuery connection ID | `42` |
| `BQ_DATASET` | Target dataset | `demo_dataset` |
| `BQ_TABLE` | Target table | `kintone_customers` |
| `BQ_LOCATION` | BigQuery location | `asia-northeast1` |

### Finding Your Connection ID

```bash
source .env.local
RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://trocco.io/api/connections/bigquery" \
  -H "Authorization: Token ${TROCCO_API_KEY}")
HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESULT" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "$BODY" | jq '.items[] | {id, name}'
else
  echo "HTTP ${HTTP_CODE}: 接続一覧APIへのアクセス権限を確認してください"
  echo "代替手段: TROCCO管理画面 > 接続情報 からBigQuery接続のIDを手動で確認し、"
  echo ".env.local の BQ_CONNECTION_ID に設定してください"
fi
```

## Terraform Configuration

### Output Option

```hcl
output_option_type = "bigquery"
output_option = {
  bigquery_output_option = {
    bigquery_connection_id = var.bq_connection_id
    dataset                = var.bq_dataset
    table                  = var.bq_table
    location               = var.bq_location
    mode                   = var.bq_load_mode
    auto_create_dataset    = true
  }
}
```

### Full Parameter Reference

#### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `bigquery_connection_id` | number | TROCCO BigQuery connection ID |
| `dataset` | string | Target dataset name |
| `table` | string | Target table name |

#### Optional (with defaults)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `mode` | string | `"append"` | Load mode (see below) |
| `auto_create_dataset` | bool | `false` | Auto-create dataset if not exists |
| `location` | string | `"US"` | BigQuery job location |
| `timeout_sec` | number | `300` | Timeout in seconds |
| `open_timeout_sec` | number | `300` | Connection open timeout |
| `read_timeout_sec` | number | `300` | Read timeout |
| `send_timeout_sec` | number | `300` | Send timeout |
| `retries` | number | `5` | Retry count |

#### Optional (partitioning & clustering)

| Parameter | Type | Description |
|-----------|------|-------------|
| `partitioning_type` | string | `"ingestion_time"` or `"time_unit_column"` |
| `time_partitioning_type` | string | `"HOUR"`, `"DAY"`, `"MONTH"`, `"YEAR"` |
| `time_partitioning_field` | string | Column name for time_unit_column partitioning |
| `time_partitioning_expiration_ms` | number | Partition expiration (ms) |
| `template_table` | string | Template table for schema reference |

### Load Modes

| Mode | Description |
|------|-------------|
| `append` | Append records to existing table (default) |
| `append_direct` | Direct append (no staging table) |
| `replace` | Drop and recreate table with new data |
| `delete_in_advance` | Delete all rows then insert |
| `merge` | Upsert based on merge keys (requires `bigquery_output_option_merge_keys`) |

### Merge Mode Example

```hcl
bigquery_output_option = {
  bigquery_connection_id          = var.bq_connection_id
  dataset                         = var.bq_dataset
  table                           = var.bq_table
  location                        = var.bq_location
  mode                            = "merge"
  bigquery_output_option_merge_keys = ["record_number"]
}
```

### Column Options (Optional)

Per-column type and format control:

```hcl
bigquery_output_option_column_options = [
  {
    name             = "created_at"
    type             = "TIMESTAMP"
    mode             = "NULLABLE"
    timestamp_format = "%Y-%m-%d %H:%M:%S"
    timezone         = "Asia/Tokyo"
  }
]
```

Column option types: `BOOLEAN`, `INTEGER`, `FLOAT`, `STRING`, `TIMESTAMP`, `DATETIME`, `DATE`, `RECORD`, `NUMERIC`
Column modes: `NULLABLE`, `REQUIRED`, `REPEATED`

## Notes

- `location` defaults to `"US"`. For Japan, set `"asia-northeast1"` explicitly.
- Partitioning and clustering settings only apply when creating a new table.
- `mode = "merge"` requires `bigquery_output_option_merge_keys` to be set.
- For initial testing, use `mode = "replace"` to ensure clean runs.
