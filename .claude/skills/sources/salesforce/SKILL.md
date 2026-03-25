---
name: source-salesforce
description: Salesforceソースのスキーマ取得・型変換・接続確認を実行する
---

# Salesforce ソースSkill

オーケストレーター (`setup-pipeline.md`) から Read で読み込まれ、Salesforce ソース固有の処理を実行する。

## 必要環境変数

| 変数 | モードA | モードB | 説明 |
|------|---------|---------|------|
| `SALESFORCE_CONNECTION_ID` | 必須 | 不要 | 既存TROCCO Salesforce接続ID |
| `SALESFORCE_USERNAME` | 不要 | 必須 | Salesforce ログインユーザー名 |
| `SALESFORCE_PASSWORD` | 不要 | 必須 | Salesforce ログインパスワード |
| `SALESFORCE_SECURITY_TOKEN` | 不要 | 必須 | Salesforce セキュリティトークン |
| `SALESFORCE_AUTH_END_POINT` | 不要 | 任意 | 認証エンドポイント（デフォルト: `https://login.salesforce.com/services/Soap/u/`） |
| `SALESFORCE_OBJECT_NAME` | 必須 | 必須 | Salesforce オブジェクト名（API名、例: `Account`） |
| `SALESFORCE_OBJECT_ACQUISITION_METHOD` | 任意 | 任意 | `all_columns`（デフォルト）または `soql` |
| `SALESFORCE_SOQL` | 条件付 | 条件付 | SOQL クエリ（`soql` メソッド時のみ必須） |

**モード判定:**
- `SALESFORCE_CONNECTION_ID` が設定済み → **モードA**（既存接続参照、推奨）
- `SALESFORCE_CONNECTION_ID` が空 → **モードB**（Terraformで新規作成）。`SALESFORCE_USERNAME` + `SALESFORCE_PASSWORD` + `SALESFORCE_SECURITY_TOKEN` が必須。

## Step 1: スキーマ取得

Salesforce SOAP Login → REST Describe API でフィールド定義を取得する。

### Step 1-1: SOAP Login

```bash
set -a && source .env.local && set +a
AUTH_EP="${SALESFORCE_AUTH_END_POINT:-https://login.salesforce.com/services/Soap/u/}"
LOGIN_RESPONSE=$(curl -s "${AUTH_EP}59.0" \
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

# セッションID・インスタンスURL抽出
SESSION_ID=$(echo "$LOGIN_RESPONSE" | grep -oP '(?<=<sessionId>)[^<]+')
INSTANCE_URL=$(echo "$LOGIN_RESPONSE" | grep -oP '(?<=<serverUrl>)https://[^/]+')

if [ -z "$SESSION_ID" ]; then
  echo "SOAP Login失敗。レスポンス:"
  echo "$LOGIN_RESPONSE"
  echo ""
  echo "確認事項:"
  echo "  - SALESFORCE_USERNAME が正しいか"
  echo "  - SALESFORCE_PASSWORD + SALESFORCE_SECURITY_TOKEN が正しいか"
  echo "  - Sandbox の場合 SALESFORCE_AUTH_END_POINT=https://test.salesforce.com/services/Soap/u/ を設定しているか"
fi

echo "Session ID: ${SESSION_ID:0:20}..."
echo "Instance URL: ${INSTANCE_URL}"
```

### Step 1-2: REST Describe API

```bash
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "${INSTANCE_URL}/services/data/v59.0/sobjects/${SALESFORCE_OBJECT_NAME}/describe/" \
  -H "Authorization: Bearer ${SESSION_ID}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '$d')
echo "$BODY" > /tmp/salesforce-describe-response.json
echo "HTTP Status: $HTTP_CODE"
```

### HTTPステータス確認

- 200: 正常 → Step 2 へ
- 401: セッション無効 → 「SOAP Loginからやり直してください」と案内して停止
- 404: オブジェクト不存在 → 「SALESFORCE_OBJECT_NAMEが正しいか確認してください（API名を使用: 例 Account, Contact, Opportunity）」と案内して停止
- その他: エラー内容を表示して停止

### スキーマ取得のフォールバック

- モードA（既存接続ID参照）で `SALESFORCE_USERNAME` / `SALESFORCE_PASSWORD` / `SALESFORCE_SECURITY_TOKEN` が未設定の場合は、スキーマ取得をスキップしてユーザーにフィールド情報を手動入力してもらう。

## Step 2: 型変換

**reference/sources/salesforce/type-mapping.md** に従い、フィールド情報を変換する。

```bash
jq -r '
  .fields[]
  | select(.type != "base64" and .type != "textarea")
  | [.name, .type, .label] | @tsv
' /tmp/salesforce-describe-response.json | sort
```

reference/sources/salesforce/type-mapping.md の変換ルールを適用し:
1. `columns` 配列を生成（Salesforceフィールド名 + TROCCOカラムタイプ + format）
2. `filter_columns` 配列を生成（snake_caseカラム名 + src + タイプ + format）

CamelCase → snake_case 変換はあなた（Claude）の推論で実行してください。
例: `CreatedDate` → `created_date`, `AccountNumber` → `account_number`, `Custom_Field__c` → `custom_field__c`

## Step 3 (src): 接続確認

### モードA: 既存接続ID参照

`SALESFORCE_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。

### モードB: Terraform新規作成

`SALESFORCE_CONNECTION_ID` が空 → API一覧を試行:

```bash
set -a && source .env.local && set +a
if [ -n "$SALESFORCE_CONNECTION_ID" ]; then
  echo "SALESFORCE_CONNECTION_ID=${SALESFORCE_CONNECTION_ID} (設定済み → このIDを使用)"
else
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/salesforce" \
    -H "Authorization: Token ${TROCCO_API_KEY}")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
  BODY=$(echo "$RESULT" | sed '$d')

  if [ "$HTTP_CODE" = "200" ]; then
    echo "$BODY" | jq '.items[] | {id, name}' 2>/dev/null || echo "既存接続なし"
  elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "API HTTP ${HTTP_CODE}: 接続一覧APIへのアクセス権限がありません"
    echo "→ TROCCO管理画面 > 接続情報 でIDを確認し .env.local に設定してください"
  else
    echo "API HTTP ${HTTP_CODE}: ${BODY}"
  fi
fi
```

- API成功 + 既存接続あり → ユーザーにID設定を案内
- API失敗（401/403） → TROCCO管理画面での手動確認を案内
- 接続なし → Terraformで新規作成。`SALESFORCE_USERNAME` + `SALESFORCE_PASSWORD` + `SALESFORCE_SECURITY_TOKEN` が必須。

## HCL情報

### input_option 構造

```
input_option_type = "salesforce"
input_option = {
  salesforce_input_option = {
    salesforce_connection_id   = local.salesforce_connection_id
    object                     = var.salesforce_object_name
    object_acquisition_method  = var.salesforce_object_acquisition_method

    columns = var.input_columns
  }
}
```

> **注意:** kintone/google_spreadsheets は `input_option_columns` を使用するが、Salesforce は `columns` を使用する（Provider仕様）。

### connection resource (モードB時)

```hcl
resource "trocco_connection" "salesforce_source" {
  count = var.salesforce_connection_id == null ? 1 : 0

  name            = var.salesforce_connection_name
  connection_type = "salesforce"
  description     = "Salesforce ${var.salesforce_object_name} - auto-generated by TROCCO Pipeline Builder"

  auth_method    = "user_password"
  user_name      = var.salesforce_username
  password       = var.salesforce_password
  security_token = var.salesforce_security_token
  auth_end_point = var.salesforce_auth_end_point
}

locals {
  salesforce_connection_id = (
    var.salesforce_connection_id != null
    ? var.salesforce_connection_id
    : trocco_connection.salesforce_source[0].id
  )
}
```

### variables.tf (Salesforce固有)

```hcl
variable "salesforce_connection_id" {
  description = "既存TROCCO Salesforce接続ID（設定時は接続作成をスキップ）"
  type        = number
  default     = null
}

variable "salesforce_connection_name" {
  description = "TROCCO上のSalesforce接続名（新規作成時のみ使用）"
  type        = string
  default     = "salesforce-auto"
}

variable "salesforce_username" {
  description = "Salesforce ログインユーザー名（新規作成時のみ使用）"
  type        = string
  default     = ""
}

variable "salesforce_password" {
  description = "Salesforce ログインパスワード（新規作成時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "salesforce_security_token" {
  description = "Salesforce セキュリティトークン（新規作成時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "salesforce_auth_end_point" {
  description = "Salesforce 認証エンドポイント（デフォルト: https://login.salesforce.com/services/Soap/u/）"
  type        = string
  default     = "https://login.salesforce.com/services/Soap/u/"
}

variable "salesforce_object_name" {
  description = "Salesforce オブジェクト名（API名、例: Account）"
  type        = string
}

variable "salesforce_object_acquisition_method" {
  description = "オブジェクト取得方法（all_columns または soql）"
  type        = string
  default     = "all_columns"
}

variable "salesforce_soql" {
  description = "SOQL クエリ（object_acquisition_method が soql の場合のみ使用）"
  type        = string
  default     = null
}
```

### TF_VAR export パターン

```bash
# Source: Salesforce
[ -n "$SALESFORCE_CONNECTION_ID" ] && export TF_VAR_salesforce_connection_id="$SALESFORCE_CONNECTION_ID"
if [ -z "$SALESFORCE_CONNECTION_ID" ]; then
  export TF_VAR_salesforce_username="$SALESFORCE_USERNAME"
  export TF_VAR_salesforce_password="$SALESFORCE_PASSWORD"
  export TF_VAR_salesforce_security_token="$SALESFORCE_SECURITY_TOKEN"
  [ -n "$SALESFORCE_AUTH_END_POINT" ] && export TF_VAR_salesforce_auth_end_point="$SALESFORCE_AUTH_END_POINT"
fi
```
