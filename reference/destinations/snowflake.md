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
| `SNOWFLAKE_AUTH_METHOD` | Auth method: `user_password` or `key_pair` | `user_password` |
| `SNOWFLAKE_PASSWORD` | Password (user_password auth) | (sensitive) |
| `SNOWFLAKE_PRIVATE_KEY` | Private key (key_pair auth) | (sensitive) |
| `SNOWFLAKE_WAREHOUSE` | Warehouse name | `COMPUTE_WH` |
| `SNOWFLAKE_DATABASE` | Database name | `DEMO_DB` |
| `SNOWFLAKE_SCHEMA` | Schema name | `PUBLIC` |
| `SNOWFLAKE_ROLE` | Role name (required) | `TROCCO_ROLE` |

## Private Key Format (key_pair auth)

`.env.local` に秘密鍵を設定する際は、改行を `\n` リテラルで記載する:
```
SNOWFLAKE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----"
```

Terraform 注入時に `printf '%b'` で実際の改行に自動変換される。
`echo -e` ではなく `printf '%b'` を使用（POSIX互換性が高い）。

手動で変換を確認する場合:
```bash
printf '%b' "$SNOWFLAKE_PRIVATE_KEY" | head -1
# → -----BEGIN PRIVATE KEY-----
```

## Terraform Configuration

### Connection

```hcl
resource "trocco_connection" "snowflake_dest" {
  name            = "snowflake-{db_name}"
  connection_type = "snowflake"

  host        = var.snowflake_host
  user_name   = var.snowflake_user
  auth_method = var.snowflake_auth_method
  password    = var.snowflake_auth_method == "user_password" ? var.snowflake_password : null
  private_key = var.snowflake_auth_method == "key_pair" ? var.snowflake_private_key : null
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

## Required Snowflake Permissions

TROCCO がデータを転送するために、指定ロールに以下の権限が必要:

```sql
-- データベース・スキーマへのアクセス
GRANT USAGE ON DATABASE {db} TO ROLE {role};
GRANT USAGE ON SCHEMA {db}.{schema} TO ROLE {role};

-- テーブル・ステージの作成（TROCCO はステージング経由でロード）
GRANT CREATE TABLE ON SCHEMA {db}.{schema} TO ROLE {role};
GRANT CREATE STAGE ON SCHEMA {db}.{schema} TO ROLE {role};  

-- ウェアハウスの利用
GRANT USAGE ON WAREHOUSE {wh} TO ROLE {role};
GRANT OPERATE ON WAREHOUSE {wh} TO ROLE {role};
```

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
