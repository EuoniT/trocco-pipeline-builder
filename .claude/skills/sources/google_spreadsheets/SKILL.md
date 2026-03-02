---
name: source-google-spreadsheets
description: Google Spreadsheetsソースのスキーマ取得・型変換・接続確認を実行する
---

# Google Spreadsheets ソースSkill

オーケストレーター (`setup-pipeline.md`) から Read で読み込まれ、Google Spreadsheets ソース固有の処理を実行する。

## 必要環境変数

| 変数 | モードA | モードB | 説明 |
|------|---------|---------|------|
| `GS_CONNECTION_ID` | 必須 | 不要 | 既存TROCCO GS接続ID |
| `GS_SERVICE_ACCOUNT_JSON_KEY` | 不要 | 必須 | サービスアカウントJSONキー |
| `GS_SPREADSHEET_ID` | 必須 | 必須 | スプレッドシートID（URLから取得） |
| `GS_WORKSHEET_TITLE` | 任意 | 任意 | ワークシート名（デフォルト: 先頭シート） |

**モード判定:**
- `GS_CONNECTION_ID` が設定済み → **モードA**（既存接続参照、推奨）
- `GS_CONNECTION_ID` が空 → **モードB**（Terraformで新規作成）。`GS_SERVICE_ACCOUNT_JSON_KEY` が必須。

### スプレッドシートID の取得方法

スプレッドシートのURLから `spreadsheets/d/` と `/edit` の間の文字列がID:
```
https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit
```

## Step 1: スキーマ取得

Google Spreadsheets にはフォーマルなスキーマ定義がないため、以下の方法でカラム情報を取得する。

### 方法1: Google Sheets API v4 によるヘッダー行取得（サービスアカウント利用時）

```bash
set -a && source .env.local && set +a
if [ -n "$GS_SERVICE_ACCOUNT_JSON_KEY" ]; then
  echo "$GS_SERVICE_ACCOUNT_JSON_KEY" > /tmp/credential.json
  gcloud auth activate-service-account --key-file=/tmp/credential.json 2>/dev/null
  ACCESS_TOKEN=$(gcloud auth print-access-token \
    --scopes="https://www.googleapis.com/auth/spreadsheets.readonly")
  rm -f /tmp/credential.json

  WORKSHEET="${GS_WORKSHEET_TITLE:-Sheet1}"
  # URLエンコード（日本語ワークシート名対応、!も含めてエンコード）
  ENCODED_RANGE=$(WORKSHEET="$WORKSHEET" python3 << 'PYEOF'
import urllib.parse, os
w = os.environ['WORKSHEET']
print(urllib.parse.quote(w + chr(33) + '1:3'))
PYEOF
)
  RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://sheets.googleapis.com/v4/spreadsheets/${GS_SPREADSHEET_ID}/values/${ENCODED_RANGE}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")
  HTTP_CODE=$(echo "$RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
  BODY=$(echo "$RESPONSE" | sed '$d')
  echo "$BODY" > /tmp/gs-header-response.json
  echo "HTTP Status: $HTTP_CODE"
fi
```

### HTTPステータス確認

- 200: 正常 → Step 2 へ
- 401/403: 認証エラー → サービスアカウントの権限を確認するよう案内
- 404: スプレッドシート不存在 → `GS_SPREADSHEET_ID` を確認するよう案内
- その他: エラー内容を表示

### 方法2: ユーザー手動入力

Google Sheets API が利用できない場合（gcloud未インストール、認証未設定、モードAでサービスアカウント未使用など）:
→ ユーザーにスプレッドシートのヘッダー行のカラム名一覧と各カラムのデータ型を確認する。

確認する情報:
1. ヘッダー行のカラム名一覧（例: ID, 顧客名, メールアドレス, 売上金額, 登録日）
2. 各カラムのデータ型（整数、小数、日付、文字列など）
3. データ開始行（通常はヘッダーの次の行 = 2）
4. ワークシート名（`GS_WORKSHEET_TITLE` が未設定の場合）

## Step 2: 型変換

**reference/sources/google_spreadsheets/type-mapping.md** に従い、カラム情報を変換する。

1. ヘッダー行の列名をそのまま `input_option_columns` の `name` に使用
2. サンプルデータ（あれば）から型を推論（reference/sources/google_spreadsheets/type-mapping.md 参照）
3. サンプルデータがない場合はカラム名から推論し、ユーザーに確認
4. `filter_columns` の `src` にはヘッダー行の列名、`name` には英語スネークケース変換した名前を設定

### filter_columns のカラム名変換ルール

Google Spreadsheets のヘッダー名から、デスティネーション側のカラム名に変換する。
Claude Code の推論で英語スネークケース変換を実行する。

変換ルール:
1. ASCII英数字のみのヘッダーはそのまま小文字化（例: `Email` → `email`）
2. 日本語ヘッダーは意味を保持した英語スネークケースに変換（例: `顧客名` → `customer_name`）
3. スペースや特殊文字はアンダースコアに置換（例: `First Name` → `first_name`）
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）

## Step 3 (src): 接続確認

### モードA: 既存接続ID参照

`GS_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。

### モードB: Terraform新規作成

`GS_CONNECTION_ID` が空 → API一覧を試行:

```bash
set -a && source .env.local && set +a
if [ -n "$GS_CONNECTION_ID" ]; then
  echo "GS_CONNECTION_ID=${GS_CONNECTION_ID} (設定済み → このIDを使用)"
else
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/google_spreadsheets" \
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
- 接続なし → Terraformで新規作成。`GS_SERVICE_ACCOUNT_JSON_KEY` が必須。

## HCL情報

### input_option 構造

```
input_option_type = "google_spreadsheets"
input_option = {
  google_spreadsheets_input_option = {
    google_spreadsheets_connection_id = local.gs_connection_id
    spreadsheets_url                  = "https://docs.google.com/spreadsheets/d/${var.gs_spreadsheet_id}/edit"
    worksheet_title                   = var.gs_worksheet_title
    start_row                         = var.gs_start_row
    start_column                      = var.gs_start_column
    default_time_zone                 = var.gs_default_time_zone
    null_string                       = var.gs_null_string

    input_option_columns = var.input_columns
  }
}
```

### spreadsheets_url の構築

`GS_SPREADSHEET_ID` から以下の形式で構築:
```
https://docs.google.com/spreadsheets/d/${var.gs_spreadsheet_id}/edit
```

### connection resource (モードB時)

```hcl
resource "trocco_connection" "google_spreadsheets_source" {
  count = var.gs_connection_id == null ? 1 : 0

  name            = var.gs_connection_name
  connection_type = "google_spreadsheets"
  description     = "Google Spreadsheets - auto-generated by TROCCO Pipeline Builder"

  service_account_json_key = var.gs_service_account_json_key
}

locals {
  gs_connection_id = (
    var.gs_connection_id != null
    ? var.gs_connection_id
    : trocco_connection.google_spreadsheets_source[0].id
  )
}
```

### variables.tf (Google Spreadsheets固有)

```hcl
variable "gs_connection_id" {
  description = "既存TROCCO Google Spreadsheets接続ID（設定時は接続作成をスキップ）"
  type        = number
  default     = null
}

variable "gs_connection_name" {
  description = "TROCCO上のGS接続名（新規作成時のみ使用）"
  type        = string
  default     = "gs-auto"
}

variable "gs_service_account_json_key" {
  description = "Googleサービスアカウント JSONキー（新規作成時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gs_spreadsheet_id" {
  description = "Google SpreadsheetのID（URLから取得）"
  type        = string
}

variable "gs_worksheet_title" {
  description = "ワークシート（タブ）名"
  type        = string
  default     = "Sheet1"
}

variable "gs_start_row" {
  description = "データ開始行（ヘッダー=1なら通常2）"
  type        = number
  default     = 2
}

variable "gs_start_column" {
  description = "開始列"
  type        = string
  default     = "A"
}

variable "gs_default_time_zone" {
  description = "日付/時刻パースのデフォルトタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

variable "gs_null_string" {
  description = "NULL扱いする文字列"
  type        = string
  default     = ""
}
```

### TF_VAR export パターン

```bash
# Source: Google Spreadsheets
[ -n "$GS_CONNECTION_ID" ] && export TF_VAR_gs_connection_id="$GS_CONNECTION_ID"
[ -z "$GS_CONNECTION_ID" ] && export TF_VAR_gs_service_account_json_key="$GS_SERVICE_ACCOUNT_JSON_KEY"
```
