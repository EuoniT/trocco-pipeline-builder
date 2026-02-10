# kintone Source

## Overview

kintone REST API の Get Form Fields エンドポイントでフィールド定義を取得し、
TROCCO の `kintone` input_option でデータを転送する。

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `KINTONE_DOMAIN` | kintone subdomain | `example.cybozu.com` |
| `KINTONE_APP_ID` | Target app ID | `1` |
| `KINTONE_API_TOKEN` | API token (read permission) | `abc123...` |

## Schema Retrieval

### API Endpoint

```
GET https://{KINTONE_DOMAIN}/k/v1/app/form/fields.json?app={KINTONE_APP_ID}
```

### Authentication

```
X-Cybozu-API-Token: {KINTONE_API_TOKEN}
```

### Response Format

```json
{
  "properties": {
    "field_code": {
      "type": "SINGLE_LINE_TEXT",
      "code": "field_code",
      "label": "Field Label"
    }
  }
}
```

### Field Extraction (jq)

```bash
# ⚠ jqフィルタはシングルクォートで囲む。!= はbash history expansionと干渉するため IN() | not を使用。
jq -r '
  .properties | to_entries[]
  | select(IN(.value.type; "FILE","STATUS_ASSIGNEE","CATEGORY","REFERENCE_TABLE") | not)
  | [.key, .value.type, .value.label] | @tsv
' /tmp/kintone-fields-response.json | sort
```

## Terraform Configuration

### Connection

```hcl
resource "trocco_connection" "kintone_source" {
  name            = "kintone-{app_name}"
  connection_type = "kintone"

  domain       = var.kintone_domain
  login_method = "token"
  token        = var.kintone_api_token
}
```

### Input Option

```hcl
input_option_type = "kintone"
input_option = {
  kintone_input_option = {
    kintone_connection_id = trocco_connection.kintone_source.id
    app_id                = var.kintone_app_id
    guest_space_id        = null
    expand_subtable       = false

    input_option_columns = var.input_columns
  }
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `kintone_connection_id` | number | Yes | TROCCO connection ID |
| `app_id` | string | Yes | kintone app ID |
| `guest_space_id` | string | No | Guest space ID (null if not applicable) |
| `expand_subtable` | bool | No | Expand subtable fields (default: false) |
| `input_option_columns` | list | Yes | Column definitions |

## Type Mapping

See `reference/type-mapping.md` for complete kintone field type to TROCCO column type mapping.

## API Call Notes

- **GET リクエストに Content-Type ヘッダを付けない。** kintone API は GET リクエストに `Content-Type: application/json` を付けると HTTP 400 エラーを返す。
- curl 例:
  ```bash
  curl -s "https://${KINTONE_DOMAIN}/k/v1/app/form/fields.json" \
    -G -d "app=${KINTONE_APP_ID}" \
    -H "X-Cybozu-API-Token: ${KINTONE_API_TOKEN}"
  ```

## Notes

- Record data is never fetched directly; only field definitions are retrieved
- API token requires only "View records" permission
- Guest space apps require `guest_space_id` parameter
- Developer License (free, 1 year): https://kintone.dev/en/developer-license-registration-form/
