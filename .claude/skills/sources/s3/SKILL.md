---
name: source-s3
description: Amazon S3ソースのスキーマ取得・型変換・接続確認を実行する
---

# Amazon S3 ソースSkill

オーケストレーター (`setup-pipeline.md`) から Read で読み込まれ、Amazon S3 ソース固有の処理を実行する。

## 必要環境変数

| 変数 | モードA | モードB | 説明 |
|------|---------|---------|------|
| `S3_CONNECTION_ID` | 必須 | 不要 | 既存TROCCO S3接続ID |
| `S3_AWS_AUTH_TYPE` | 不要 | 必須 | `iam_user` or `assume_role` |
| `S3_AWS_ACCESS_KEY_ID` | 不要 | 条件付 | IAM User時のアクセスキー |
| `S3_AWS_SECRET_ACCESS_KEY` | 不要 | 条件付 | IAM User時のシークレットキー |
| `S3_AWS_ACCOUNT_ID` | 不要 | 条件付 | AssumeRole時のAWSアカウントID |
| `S3_AWS_ROLE_NAME` | 不要 | 条件付 | AssumeRole時のIAMロール名 |
| `S3_BUCKET` | 必須 | 必須 | S3バケット名 |
| `S3_PATH_PREFIX` | 必須 | 必須 | パスプレフィックス |
| `S3_REGION` | 任意 | 任意 | AWSリージョン（デフォルト: ap-northeast-1） |
| `S3_FILE_FORMAT` | 必須 | 必須 | csv/jsonl/jsonpath/parquet/excel/ltsv/xml |

**モード判定:**
- `S3_CONNECTION_ID` が設定済み → **モードA**（既存接続参照、推奨）
- `S3_CONNECTION_ID` が空 → **モードB**（Terraformで新規作成）。`S3_AWS_AUTH_TYPE` + 対応する認証情報が必須。

## Step 1: スキーマ取得

S3 はファイルベースのソースであり、ファイルフォーマットによってスキーマ取得方法が異なる。

### 方法1: AWS CLI + シェルコマンドでサンプルファイル取得

AWS CLI がインストール済みで、認証が設定されている場合に使用。

```bash
set -a && source .env.local && set +a

# AWS CLIが利用可能か確認
if command -v aws &>/dev/null; then
  # 先頭ファイルを取得
  FIRST_FILE=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PATH_PREFIX}" --region "${S3_REGION:-ap-northeast-1}" \
    | grep -v '/$' | head -1 | awk '{print $NF}')

  if [ -n "$FIRST_FILE" ]; then
    aws s3 cp "s3://${S3_BUCKET}/${S3_PATH_PREFIX}${FIRST_FILE}" /tmp/s3-sample-file \
      --region "${S3_REGION:-ap-northeast-1}"
    echo "Downloaded: ${FIRST_FILE}"
  else
    echo "No files found at s3://${S3_BUCKET}/${S3_PATH_PREFIX}"
  fi
else
  echo "AWS CLI not found → フォールバック: ユーザー手動入力"
fi
```

#### CSV の場合

```bash
# ヘッダー行を取得
head -1 /tmp/s3-sample-file
# サンプルデータを取得（2-6行目）
sed -n '2,6p' /tmp/s3-sample-file
```

ヘッダー行からカラム名を取得し、サンプルデータから型を推論する。

#### JSONL の場合

```bash
# キー名と型を取得
head -1 /tmp/s3-sample-file | jq 'keys[]'
# 各キーの型を確認
head -1 /tmp/s3-sample-file | jq 'to_entries[] | {key, type: (.value | type)}'
```

#### LTSV の場合

```bash
# ラベル名を取得
head -1 /tmp/s3-sample-file | tr '\t' '\n' | cut -d: -f1
```

### 方法2: ユーザー手動入力（フォールバック）

以下の場合にフォールバック:
- AWS CLI 未インストール
- AWS認証未設定
- Parquet / Excel / JSONPath / XML フォーマット

確認する情報:
1. カラム名一覧（例: id, name, email, amount, created_at）
2. 各カラムのデータ型（整数、小数、日付、文字列など）
3. CSV の場合: 区切り文字（デフォルト: カンマ）、ヘッダー行の有無
4. JSONPath の場合: root式（JSONPath表現、例: `$.data[*]`）

### HTTPステータス確認（AWS CLI）

- ファイル取得成功 → Step 2 へ
- AccessDenied → バケットポリシーまたはIAM権限を確認するよう案内
- NoSuchBucket → `S3_BUCKET` を確認するよう案内
- AWS CLI 未インストール → 方法2（手動入力）へ

## Step 2: 型変換

**reference/sources/s3/type-mapping.md** に従い、カラム情報を変換する。

### CSV / LTSV の場合
1. ヘッダー行/ラベル名をそのまま `columns` の `name` に使用
2. サンプルデータから型を推論（CSV型推論ルール適用）
3. 推論結果をユーザーに提示し、修正があれば反映

### JSONL の場合
1. JSONキー名を `columns` の `name` に使用
2. JSON値の型から TROCCO型を直接マッピング（JSONL型推論ルール適用）
3. 推論結果をユーザーに提示し、修正があれば反映

### Parquet / Excel / JSONPath / XML の場合
1. ユーザーから提供されたカラム情報をそのまま使用
2. 型の妥当性を確認し、必要に応じて修正を提案

### filter_columns のカラム名変換ルール

ファイルのヘッダー/キー名から、デスティネーション側のカラム名に変換する。
Claude Code の推論で英語スネークケース変換を実行する。

変換ルール:
1. ASCII英数字のみのヘッダーはそのまま小文字化（例: `Email` → `email`）
2. 日本語ヘッダーは意味を保持した英語スネークケースに変換（例: `顧客名` → `customer_name`）
3. スペースや特殊文字はアンダースコアに置換（例: `First Name` → `first_name`）
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）
5. JSONL のネストキーはドット区切りをアンダースコアに変換（例: `address.city` → `address_city`）

## Step 3 (src): 接続確認

### モードA: 既存接続ID参照

`S3_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。

### モードB: Terraform新規作成

`S3_CONNECTION_ID` が空 → API一覧を試行:

```bash
set -a && source .env.local && set +a
if [ -n "$S3_CONNECTION_ID" ]; then
  echo "S3_CONNECTION_ID=${S3_CONNECTION_ID} (設定済み → このIDを使用)"
else
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/s3" \
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
- 接続なし → Terraformで新規作成。`S3_AWS_AUTH_TYPE` + 対応認証情報が必須。

## HCL情報

### input_option 構造

**重要設計方針:** パーサー選択にTerraformの条件分岐は使わない。ファイル形式はHCL生成時に確定しているため、選択されたパーサーのブロックのみ生成する。

```
input_option_type = "s3"
input_option = {
  s3_input_option = {
    s3_connection_id = local.s3_connection_id
    bucket           = var.s3_bucket
    region           = var.s3_region
    path_prefix      = var.s3_path_prefix

    # ⚠ decoder は必須。省略すると "Provider produced inconsistent result" エラー
    decoder = {
      match_name = ""
    }

    # パーサーは1つだけ（ファイル形式に応じて選択）
    csv_parser = {          # ← CSV の場合のみ
      columns           = var.input_columns
      delimiter         = var.s3_csv_delimiter
      skip_header_lines = var.s3_csv_skip_header_lines
      default_time_zone = var.s3_default_time_zone
    }
  }
}
```

### パーサー別 HCL ブロック

#### CSV
```hcl
csv_parser = {
  columns           = var.input_columns
  delimiter         = var.s3_csv_delimiter
  quote             = var.s3_csv_quote
  escape            = var.s3_csv_escape
  skip_header_lines = var.s3_csv_skip_header_lines
  default_time_zone = var.s3_default_time_zone
}
```

#### JSONL
```hcl
jsonl_parser = {
  columns           = var.input_columns
  default_time_zone = var.s3_default_time_zone
}
```

#### JSONPath
```hcl
jsonpath_parser = {
  columns           = var.input_columns
  root              = var.s3_jsonpath_root
  default_time_zone = var.s3_default_time_zone
}
```

#### Parquet
```hcl
parquet_parser = {
  columns = var.input_columns
}
```

#### Excel
```hcl
excel_parser = {
  columns           = var.input_columns_excel  # formula_handling 付き
  sheet_name        = var.s3_excel_sheet_name   # 必須: シート名
  skip_header_lines = var.s3_excel_skip_header_lines
  default_time_zone = var.s3_default_time_zone
}
```

**Excel columns 拡張構造:**
Excel パーサーの columns は `formula_handling` フィールドが追加で必要:
```hcl
variable "input_columns_excel" {
  type = list(object({
    name              = string
    type              = string
    format            = optional(string)
    formula_handling  = string  # "cashed_value"（推奨）or "evaluate"
  }))
}
```

> **注意:** Provider の命名は `cashed_value`（typo）であり、`cached_value` ではない。

#### LTSV
```hcl
ltsv_parser = {
  columns = var.input_columns
}
```

#### XML
```hcl
xml_parser = {
  columns = var.input_columns
}
```

### connection resource (モードB時)

**⚠ Provider 互換性注意:** `aws_assume_role = ... : null` や `aws_iam_user = ... : null` の三項演算子パターンは Provider エラーを引き起こす場合がある。`aws_auth_type` に応じて使用する認証ブロックのみ生成すること。

**IAM User 認証の場合:**
```hcl
resource "trocco_connection" "s3_source" {
  count = var.s3_connection_id == null ? 1 : 0

  name            = var.s3_connection_name
  connection_type = "s3"
  description     = "S3 ${var.s3_bucket} - auto-generated by TROCCO Pipeline Builder"

  aws_auth_type = "iam_user"

  aws_iam_user = {
    access_key_id     = var.s3_aws_access_key_id
    secret_access_key = var.s3_aws_secret_access_key
  }
}
```

**AssumeRole 認証の場合:**
```hcl
resource "trocco_connection" "s3_source" {
  count = var.s3_connection_id == null ? 1 : 0

  name            = var.s3_connection_name
  connection_type = "s3"
  description     = "S3 ${var.s3_bucket} - auto-generated by TROCCO Pipeline Builder"

  aws_auth_type = "assume_role"

  aws_assume_role = {
    account_id = var.s3_aws_account_id
    role_name  = var.s3_aws_role_name
  }
}
```

```hcl
locals {
  s3_connection_id = (
    var.s3_connection_id != null
    ? var.s3_connection_id
    : trocco_connection.s3_source[0].id
  )
}
```

### variables.tf (S3固有)

```hcl
variable "s3_connection_id" {
  description = "既存TROCCO S3接続ID（設定時は接続作成をスキップ）"
  type        = number
  default     = null
}

variable "s3_connection_name" {
  description = "TROCCO上のS3接続名（新規作成時のみ使用）"
  type        = string
  default     = "s3-auto"
}

variable "s3_aws_auth_type" {
  description = "AWS認証方式: iam_user or assume_role（新規作成時のみ使用）"
  type        = string
  default     = "iam_user"

  validation {
    condition     = contains(["iam_user", "assume_role"], var.s3_aws_auth_type)
    error_message = "s3_aws_auth_type must be 'iam_user' or 'assume_role'."
  }
}

variable "s3_aws_access_key_id" {
  description = "AWSアクセスキーID（iam_user時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_aws_secret_access_key" {
  description = "AWSシークレットアクセスキー（iam_user時のみ使用）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_aws_account_id" {
  description = "AWSアカウントID（assume_role時のみ使用）"
  type        = string
  default     = ""
}

variable "s3_aws_role_name" {
  description = "IAMロール名（assume_role時のみ使用）"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3バケット名"
  type        = string
}

variable "s3_path_prefix" {
  description = "S3パスプレフィックス"
  type        = string
}

variable "s3_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "s3_default_time_zone" {
  description = "デフォルトタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

# CSV固有
variable "s3_csv_delimiter" {
  description = "CSV区切り文字"
  type        = string
  default     = ","
}

variable "s3_csv_skip_header_lines" {
  description = "CSVスキップヘッダー行数"
  type        = number
  default     = 1
}

# Excel固有
variable "s3_excel_sheet_name" {
  description = "Excelシート名（excel_parser 使用時は必須）"
  type        = string
  default     = "Sheet1"
}

variable "s3_excel_skip_header_lines" {
  description = "Excelスキップヘッダー行数"
  type        = number
  default     = 1
}

variable "input_columns_excel" {
  description = "Excel入力カラム定義（formula_handling 付き）"
  type = list(object({
    name              = string
    type              = string
    format            = optional(string)
    formula_handling  = string  # "cashed_value" or "evaluate"
  }))
  default = []
}
```

### TF_VAR export パターン

```bash
# Source: Amazon S3
[ -n "$S3_CONNECTION_ID" ] && export TF_VAR_s3_connection_id="$S3_CONNECTION_ID"
if [ -z "$S3_CONNECTION_ID" ]; then
  export TF_VAR_s3_aws_auth_type="${S3_AWS_AUTH_TYPE:-iam_user}"
  if [ "$S3_AWS_AUTH_TYPE" = "iam_user" ]; then
    export TF_VAR_s3_aws_access_key_id="$S3_AWS_ACCESS_KEY_ID"
    export TF_VAR_s3_aws_secret_access_key="$S3_AWS_SECRET_ACCESS_KEY"
  else
    export TF_VAR_s3_aws_account_id="$S3_AWS_ACCOUNT_ID"
    export TF_VAR_s3_aws_role_name="$S3_AWS_ROLE_NAME"
  fi
fi
```
