---
name: destination-bigquery
description: BigQueryデスティネーションの接続確認・HCL情報を提供する
---

# BigQuery デスティネーションSkill

オーケストレーター (`setup-pipeline.md`) から Read で読み込まれ、BigQuery デスティネーション固有の処理を実行する。

## 必要環境変数

| 変数 | 必須 | 説明 |
|------|------|------|
| `BQ_CONNECTION_ID` | 必須 | TROCCO BigQuery接続ID（TROCCO UIで事前作成） |
| `BQ_DATASET` | 必須 | 転送先データセット名 |
| `BQ_TABLE` | 必須 | 転送先テーブル名 |
| `BQ_LOCATION` | 任意 | BigQueryロケーション（デフォルト: `asia-northeast1`） |

**注意:** BigQuery接続はTROCCO UIでOAuth/サービスアカウントで作成済みのものを使用する。
Terraform `trocco_connection` リソースでの新規作成は不要（モードAのみ）。

## Step 3 (dest): 接続確認

BigQuery接続はTROCCO UIで作成済みのものを参照する:

- `BQ_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。
- `BQ_CONNECTION_ID` が未設定 → API一覧を試行:

```bash
set -a && source .env.local && set +a
if [ -n "$BQ_CONNECTION_ID" ]; then
  echo "BQ_CONNECTION_ID=${BQ_CONNECTION_ID} (設定済み → このIDを使用)"
else
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/bigquery" \
    -H "Authorization: Token ${TROCCO_API_KEY}")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
  BODY=$(echo "$RESULT" | sed '$d')

  if [ "$HTTP_CODE" = "200" ]; then
    echo "$BODY" | jq '.items[] | {id, name}' 2>/dev/null || echo "既存接続なし → TROCCO管理画面で作成してください"
  elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "API HTTP ${HTTP_CODE}: 接続一覧APIへのアクセス権限がありません"
    echo "→ TROCCO管理画面 > 接続情報 でBigQuery接続のIDを確認し .env.local に設定してください"
  else
    echo "API HTTP ${HTTP_CODE}: ${BODY}"
  fi
fi
```

- API成功 + 接続あり → 「.env.localの`BQ_CONNECTION_ID`にIDを設定してください」と案内
- API失敗（401/403） → 「TROCCO管理画面 > 接続情報 でBigQuery接続IDを確認してください」と案内
- 接続なし → 「TROCCO管理画面 > 接続情報 > 新規作成 > BigQuery でOAuth接続を作成してください」と案内して停止

## HCL情報

### output_option 構造

```
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

### 重要な注意事項

- `location` のデフォルトは `"US"`。日本環境では `"asia-northeast1"` を明示指定する。
- `auto_create_dataset = true` でデータセット自動作成を有効化。
- BigQuery connection resource は不要（既存接続参照のみ）。

### variables.tf (BigQuery固有)

```hcl
variable "bq_connection_id" {
  description = "TROCCO BigQuery connection ID (create via TROCCO UI first)"
  type        = number
}

variable "bq_dataset" {
  description = "BigQuery dataset name"
  type        = string
}

variable "bq_table" {
  description = "BigQuery table name"
  type        = string
}

variable "bq_location" {
  description = "BigQuery location (e.g., US, asia-northeast1)"
  type        = string
  default     = "asia-northeast1"
}

variable "bq_load_mode" {
  description = "Load mode (append, append_direct, replace, delete_in_advance, merge)"
  type        = string
  default     = "replace"
}
```

### TF_VAR export パターン

BigQueryはTROCCO UIで作成済みの接続IDを参照するため、追加のTF_VAR注入は不要。
`bq_connection_id` は `terraform.tfvars` に記載する（sensitive値ではない）。

## ロードモード

| mode | 説明 |
|------|------|
| `append` | 既存テーブルに追記（デフォルト） |
| `append_direct` | 直接追記（中間テーブルなし） |
| `replace` | テーブルをDROP→CREATE→INSERT |
| `delete_in_advance` | 全データ削除→INSERT |
| `merge` | merge_keysベースのUPSERT |

### merge mode の場合

`bigquery_output_option_merge_keys` が必要:

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
