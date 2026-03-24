# Salesforce Source

## Overview

Salesforce REST API の Describe エンドポイントでフィールド定義を取得し、
TROCCO の `salesforce` input_option でデータを転送する。

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SALESFORCE_USERNAME` | Salesforce ログインユーザー名 | `user@example.com` |
| `SALESFORCE_PASSWORD` | Salesforce ログインパスワード | `your_password` |
| `SALESFORCE_SECURITY_TOKEN` | Salesforce セキュリティトークン | `abc123...` |
| `SALESFORCE_OBJECT_NAME` | 対象オブジェクト名（API名） | `Account` |

## Schema Retrieval

### Step 1: SOAP Login でセッション取得

```bash
LOGIN_RESPONSE=$(curl -s "${SALESFORCE_AUTH_END_POINT:-https://login.salesforce.com/services/Soap/u/}59.0" \
  -H "Content-Type: text/xml; charset=UTF-8" \
  -H "SOAPAction: login" \
  -d '<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:urn="urn:partner.soap.sforce.com">
  <soapenv:Body>
    <urn:login>
      <urn:username>'"${SALESFORCE_USERNAME}"'</urn:username>
      <urn:password>'"${SALESFORCE_PASSWORD}${SALESFORCE_SECURITY_TOKEN}"'</urn:password>
    </urn:login>
  </soapenv:Body>
</soapenv:Envelope>')

SESSION_ID=$(echo "$LOGIN_RESPONSE" | grep -oP '(?<=<sessionId>)[^<]+')
INSTANCE_URL=$(echo "$LOGIN_RESPONSE" | grep -oP '(?<=<serverUrl>)https://[^/]+')
```

### Step 2: REST Describe API でフィールド定義取得

```bash
curl -s "${INSTANCE_URL}/services/data/v59.0/sobjects/${SALESFORCE_OBJECT_NAME}/describe/" \
  -H "Authorization: Bearer ${SESSION_ID}" \
  > /tmp/salesforce-describe-response.json
```

### Response Format

```json
{
  "fields": [
    {
      "name": "Id",
      "type": "id",
      "label": "Record ID",
      "length": 18,
      "nillable": false
    },
    {
      "name": "Name",
      "type": "string",
      "label": "Account Name",
      "length": 255,
      "nillable": false
    }
  ]
}
```

### Field Extraction (jq)

```bash
jq -r '
  .fields[]
  | select(.type != "base64")
  | [.name, .type, .label] | @tsv
' /tmp/salesforce-describe-response.json | sort
```

## Connection Method

### Mode A: 既存接続ID参照（推奨）

TROCCO管理画面で事前に Salesforce 接続を作成し、`SALESFORCE_CONNECTION_ID` を設定。

### Mode B: Terraform 新規作成

`SALESFORCE_CONNECTION_ID` が未設定の場合、以下の環境変数で新規接続を作成:
- `SALESFORCE_USERNAME` — ログインユーザー名
- `SALESFORCE_PASSWORD` — ログインパスワード
- `SALESFORCE_SECURITY_TOKEN` — セキュリティトークン
- `SALESFORCE_AUTH_END_POINT` — 認証エンドポイント（任意）

## Terraform Configuration

### Connection

```hcl
resource "trocco_connection" "salesforce_source" {
  name            = "salesforce-{object_name}"
  connection_type = "salesforce"

  auth_method    = "user_password"
  user_name      = var.salesforce_username
  password       = var.salesforce_password
  security_token = var.salesforce_security_token
  auth_end_point = var.salesforce_auth_end_point
}
```

### Input Option

```hcl
input_option_type = "salesforce"
input_option = {
  salesforce_input_option = {
    salesforce_connection_id    = local.salesforce_connection_id
    object                     = var.salesforce_object_name
    object_acquisition_method  = var.salesforce_object_acquisition_method

    columns = var.input_columns
  }
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `salesforce_connection_id` | number | Yes | TROCCO connection ID |
| `object` | string | Yes | Salesforce オブジェクト名（API名） |
| `object_acquisition_method` | string | No | `all_columns`（デフォルト）または `soql` |
| `soql` | string | Conditional | SOQL クエリ（`object_acquisition_method = "soql"` の場合必須） |
| `columns` | list | Yes | カラム定義（`input_option_columns` ではなく `columns` を使用） |
| `api_version` | string | No | Salesforce API バージョン |
| `include_deleted_or_archived_records` | bool | No | 削除済み・アーカイブ済みレコードを含めるか |
| `is_convert_type_custom_columns` | bool | No | カスタムカラムの型変換を有効にするか |

## Type Mapping

See `reference/sources/salesforce/type-mapping.md` for complete Salesforce field type to TROCCO column type mapping.

## Notes

- **`columns` を使用:** kintone/google_spreadsheets の `input_option_columns` ではなく、Salesforce は `columns` を使用（Provider仕様）
- **API バージョン:** デフォルトは v59.0。`api_version` で変更可能
- **Sandbox 対応:** `auth_end_point` を `https://test.salesforce.com/services/Soap/u/` に変更
- **API 制限:** Salesforce API のコール制限（24時間あたり）に注意。Describe API は1コール消費
- **セキュリティトークン:** Salesforce の個人設定 > セキュリティトークンのリセット で取得
- **SOQL モード:** `object_acquisition_method = "soql"` の場合、`soql` フィールドにクエリを記述。`all_columns` の場合はSOQLが自動補完される
