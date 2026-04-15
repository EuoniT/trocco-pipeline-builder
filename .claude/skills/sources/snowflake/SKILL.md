---
name: source-snowflake
description: Snowflakeソースのスキーマ取得・型変換・接続確認を実行する
---

# Snowflake ソースSkill

オーケストレーター (`setup-pipeline.md`) から Read で読み込まれ、Snowflake ソース固有の処理を実行する。

**注意:** Snowflake はデスティネーションとしても実装済み（`SNOWFLAKE_*` プレフィックス）。
ソース側は `SNOWFLAKE_SRC_*` プレフィックスを使用し、同一パイプラインでの併用時の衝突を回避する。

## 必要環境変数

| 変数 | モードA | モードB | 説明 |
|------|---------|---------|------|
| `SNOWFLAKE_SRC_CONNECTION_ID` | 必須 | 不要 | 既存TROCCO Snowflake接続ID |
| `SNOWFLAKE_SRC_HOST` | 不要 | 必須 | Snowflakeアカウントのホスト名 |
| `SNOWFLAKE_SRC_USER` | 不要 | 必須 | Snowflakeユーザー名 |
| `SNOWFLAKE_SRC_AUTH_METHOD` | 不要 | 任意 | 認証方式: `user_password`（デフォルト）/ `key_pair` |
| `SNOWFLAKE_SRC_PASSWORD` | 不要 | 条件付 | パスワード（user_password時） |
| `SNOWFLAKE_SRC_PRIVATE_KEY` | 不要 | 条件付 | 秘密鍵（key_pair時、`\n` リテラルで改行を記載） |
| `SNOWFLAKE_SRC_DATABASE` | 必須 | 必須 | データベース名 |
| `SNOWFLAKE_SRC_SCHEMA` | 必須 | 必須 | スキーマ名 |
| `SNOWFLAKE_SRC_QUERY` | 必須 | 必須 | SQLクエリ（例: `SELECT * FROM my_table`） |
| `SNOWFLAKE_SRC_WAREHOUSE` | 必須 | 必須 | ウェアハウス名 |
| `SNOWFLAKE_SRC_ROLE` | 必須 | 必須 | ロール名 |

**モード判定:**
- `SNOWFLAKE_SRC_CONNECTION_ID` が設定済み → **モードA**（既存接続参照、推奨）
- `SNOWFLAKE_SRC_CONNECTION_ID` が空 → **モードB**（Terraformで新規作成）。`SNOWFLAKE_SRC_HOST` + `SNOWFLAKE_SRC_USER` + 認証情報が必須。

## Step 1: スキーマ取得

Snowflake SQL REST API で `INFORMATION_SCHEMA.COLUMNS` をクエリし、カラム定義を取得する。

### テーブル指定の場合

```bash
set -a && source .env.local && set +a

# key_pair 認証の場合: JWT を生成
if [ "$SNOWFLAKE_SRC_AUTH_METHOD" = "key_pair" ]; then
  # 秘密鍵を一時ファイルに展開
  PRIVKEY_FILE=$(mktemp)
  printf '%b' "$SNOWFLAKE_SRC_PRIVATE_KEY" > "$PRIVKEY_FILE"

  # 公開鍵のフィンガープリント（SHA-256）を取得
  PUBKEY_FP=$(openssl rsa -in "$PRIVKEY_FILE" -pubout 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64)
  ACCOUNT_UPPER=$(echo "$SNOWFLAKE_SRC_HOST" | sed 's/\.snowflakecomputing\.com$//' | tr '[:lower:]' '[:upper:]' | tr '.' '-')
  USER_UPPER=$(echo "$SNOWFLAKE_SRC_USER" | tr '[:lower:]' '[:upper:]')
  QUALIFIED_USERNAME="${ACCOUNT_UPPER}.${USER_UPPER}"

  # JWT 生成
  NOW=$(date +%s)
  EXP=$((NOW + 3600))
  HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl enc -base64 -A | tr '+/' '-_' | tr -d '=')
  PAYLOAD=$(echo -n "{\"iss\":\"${QUALIFIED_USERNAME}.SHA256:${PUBKEY_FP}\",\"sub\":\"${QUALIFIED_USERNAME}\",\"iat\":${NOW},\"exp\":${EXP}}" | openssl enc -base64 -A | tr '+/' '-_' | tr -d '=')
  SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -sign "$PRIVKEY_FILE" | openssl enc -base64 -A | tr '+/' '-_' | tr -d '=')
  JWT_TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

  rm -f "$PRIVKEY_FILE"

  AUTH_HEADER="Authorization: Bearer ${JWT_TOKEN}"
  TOKEN_TYPE_HEADER="X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT"
else
  echo "user_password 認証では SQL REST API を直接利用できません。"
  echo "snowsql CLI または手動入力をご利用ください。"
  # snowsql フォールバック:
  # snowsql -a "$SNOWFLAKE_SRC_HOST" -u "$SNOWFLAKE_SRC_USER" -d "$SNOWFLAKE_SRC_DATABASE" -s "INFORMATION_SCHEMA" -w "$SNOWFLAKE_SRC_WAREHOUSE" -r "$SNOWFLAKE_SRC_ROLE" -q "SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE FROM ${SNOWFLAKE_SRC_DATABASE}.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='${SNOWFLAKE_SRC_SCHEMA}' AND TABLE_NAME='${SNOWFLAKE_SRC_TABLE}' ORDER BY ORDINAL_POSITION" -o output_format=json
fi
```

### SQL REST API 呼び出し（key_pair 認証時）

```bash
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "https://${SNOWFLAKE_SRC_HOST}/api/v2/statements" \
  -H "${AUTH_HEADER}" \
  -H "${TOKEN_TYPE_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "statement": "SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE FROM '"${SNOWFLAKE_SRC_DATABASE}"'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '"'"''"${SNOWFLAKE_SRC_SCHEMA}"''"'"' AND TABLE_NAME = '"'"''"${SNOWFLAKE_SRC_TABLE}"''"'"' ORDER BY ORDINAL_POSITION",
    "timeout": 60,
    "database": "'"${SNOWFLAKE_SRC_DATABASE}"'",
    "schema": "INFORMATION_SCHEMA",
    "warehouse": "'"${SNOWFLAKE_SRC_WAREHOUSE}"'",
    "role": "'"${SNOWFLAKE_SRC_ROLE}"'"
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '$d')
echo "$BODY" > /tmp/snowflake-columns-response.json
echo "HTTP Status: $HTTP_CODE"
```

### カスタムクエリの場合

カスタムクエリ使用時はスキーマ自動取得ができないため、ユーザーにカラム情報を手動入力してもらう。

### HTTPステータス確認

- 200: 正常 → Step 2 へ
- 401/403: 認証エラー → 認証情報（JWT/ホスト名/ユーザー名）の確認を案内して停止
- 404: エンドポイント不存在 → ホスト名の確認を案内して停止
- 422: SQL エラー → クエリ内容（データベース名/スキーマ名/テーブル名）の確認を案内
- その他: エラー内容を表示して停止

### スキーマ取得のフォールバック

以下の場合はスキーマ自動取得をスキップし、ユーザーにカラム情報を手動入力してもらう:
- user_password 認証で snowsql CLI が利用不可
- カスタムクエリ使用時
- REST API 呼び出しが失敗した場合

## Step 2: 型変換

**reference/sources/snowflake/type-mapping.md** に従い、カラム情報を変換する。

REST API レスポンスからカラム情報を抽出:
```bash
jq -r '
  .data[]
  | [.[0], .[1], .[2], .[3]] | @tsv
' /tmp/snowflake-columns-response.json | sort
```

reference/sources/snowflake/type-mapping.md の変換ルールを適用し:
1. `columns` 配列を生成（Snowflakeカラム名 + TROCCOカラムタイプ + format）
2. `filter_columns` 配列を生成（小文字カラム名 + src + タイプ + format）

カラム名の変換: Snowflake カラム名を小文字に変換（例: `ACCOUNT_ID` → `account_id`）。

## Step 3 (src): 接続確認

### モードA: 既存接続ID参照

`SNOWFLAKE_SRC_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。

### モードB: Terraform新規作成

`SNOWFLAKE_SRC_CONNECTION_ID` が空 → API一覧を試行:

```bash
set -a && source .env.local && set +a
if [ -n "$SNOWFLAKE_SRC_CONNECTION_ID" ]; then
  echo "SNOWFLAKE_SRC_CONNECTION_ID=${SNOWFLAKE_SRC_CONNECTION_ID} (設定済み → このIDを使用)"
else
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/snowflake" \
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
- 接続なし → Terraformで新規作成。`SNOWFLAKE_SRC_HOST` + `SNOWFLAKE_SRC_USER` + 認証情報が必須。

## HCL情報

### input_option 構造

```
input_option_type = "snowflake"
input_option = {
  snowflake_input_option = {
    snowflake_connection_id = local.snowflake_src_connection_id
    database                = var.snowflake_src_database
    schema                  = var.snowflake_src_schema
    query                   = var.snowflake_src_query
    warehouse               = var.snowflake_src_warehouse

    input_option_columns = var.input_columns
  }
}
```

> **注意:** Snowflake は `input_option_columns`（name + type）と `query`（SQLクエリ）を使用する。`table` や `custom_query` ではなく、常に `query` でSQLを指定する。

### connection resource (モードB時)

```hcl
resource "trocco_connection" "snowflake_source" {
  count = var.snowflake_src_connection_id == null ? 1 : 0

  name            = var.snowflake_src_connection_name
  connection_type = "snowflake"
  description     = "Snowflake ${var.snowflake_src_database}.${var.snowflake_src_schema} (source) - auto-generated by TROCCO Pipeline Builder"

  host        = var.snowflake_src_host
  user_name   = var.snowflake_src_user
  auth_method = var.snowflake_src_auth_method
  password    = var.snowflake_src_auth_method == "user_password" ? var.snowflake_src_password : null
  private_key = var.snowflake_src_auth_method == "key_pair" ? var.snowflake_src_private_key : null
  role        = var.snowflake_src_role
}

locals {
  snowflake_src_connection_id = (
    var.snowflake_src_connection_id != null
    ? var.snowflake_src_connection_id
    : trocco_connection.snowflake_source[0].id
  )
}
```

### variables.tf (Snowflake Source固有)

```hcl
variable "snowflake_src_connection_id" {
  description = "既存TROCCO Snowflake接続ID（設定時は接続作成をスキップ）"
  type        = number
  default     = null
}

variable "snowflake_src_connection_name" {
  description = "TROCCO上のSnowflake接続名（新規作成時のみ使用）"
  type        = string
  default     = "snowflake-src-auto"
}

variable "snowflake_src_host" {
  description = "Snowflake ホスト名（新規作成時のみ使用）"
  type        = string
  default     = ""
}

variable "snowflake_src_user" {
  description = "Snowflake ユーザー名（新規作成時のみ使用）"
  type        = string
  default     = ""
}

variable "snowflake_src_auth_method" {
  description = "Snowflake 認証方式: user_password or key_pair"
  type        = string
  default     = "user_password"
}

variable "snowflake_src_password" {
  description = "Snowflake パスワード（user_password 時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_src_private_key" {
  description = "Snowflake 秘密鍵（key_pair 時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_src_role" {
  description = "Snowflake ロール名"
  type        = string
}

variable "snowflake_src_warehouse" {
  description = "Snowflake ウェアハウス名"
  type        = string
}

variable "snowflake_src_database" {
  description = "Snowflake データベース名"
  type        = string
}

variable "snowflake_src_schema" {
  description = "Snowflake スキーマ名"
  type        = string
  default     = "PUBLIC"
}

variable "snowflake_src_query" {
  description = "SQLクエリ（例: SELECT * FROM my_table）"
  type        = string
}
```

### TF_VAR export パターン

```bash
# Source: Snowflake
# 共通変数（input_option 用 — 両モード必須）
export TF_VAR_snowflake_src_database="$SNOWFLAKE_SRC_DATABASE"
export TF_VAR_snowflake_src_schema="$SNOWFLAKE_SRC_SCHEMA"
export TF_VAR_snowflake_src_warehouse="$SNOWFLAKE_SRC_WAREHOUSE"
export TF_VAR_snowflake_src_role="$SNOWFLAKE_SRC_ROLE"
export TF_VAR_snowflake_src_query="$SNOWFLAKE_SRC_QUERY"

# 接続情報（モードに応じて分岐）
if [ -n "$SNOWFLAKE_SRC_CONNECTION_ID" ]; then
  export TF_VAR_snowflake_src_connection_id="$SNOWFLAKE_SRC_CONNECTION_ID"  # モードA
else
  export TF_VAR_snowflake_src_host="$SNOWFLAKE_SRC_HOST"
  export TF_VAR_snowflake_src_user="$SNOWFLAKE_SRC_USER"
  export TF_VAR_snowflake_src_auth_method="${SNOWFLAKE_SRC_AUTH_METHOD:-user_password}"
  if [ "$SNOWFLAKE_SRC_AUTH_METHOD" = "key_pair" ]; then
    export TF_VAR_snowflake_src_private_key="$(printf '%b' "$SNOWFLAKE_SRC_PRIVATE_KEY")"
  else
    export TF_VAR_snowflake_src_password="$SNOWFLAKE_SRC_PASSWORD"
  fi
fi
```
