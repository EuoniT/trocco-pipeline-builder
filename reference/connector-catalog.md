# TROCCO 対応コネクタカタログ

## ソース（転送元）

| コネクタ名 | Terraform input_option_type | 必要な環境変数 | スキーマ自動取得 |
|-----------|---------------------------|---------------|----------------|
| kintone | kintone | KINTONE_DOMAIN, KINTONE_APP_ID, KINTONE_API_TOKEN | Get Form Fields API |
| MySQL | mysql | MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE | TROCCO側で自動取得 |
| PostgreSQL | postgresql | PG_HOST, PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE | TROCCO側で自動取得 |
| BigQuery | bigquery | BQ_PROJECT, BQ_DATASET, BQ_TABLE | TROCCO側で自動取得 |
| Salesforce | salesforce | SF_CONNECTION_ID（TROCCO上でOAuth済み） | TROCCO側で自動取得 |
| Google Spreadsheets | google_spreadsheets | GS_CONNECTION_ID, GS_SPREADSHEET_ID | シート構造から推定 |
| Amazon S3 | s3 | S3_CONNECTION_ID, S3_BUCKET, S3_PATH | ヘッダ行から推定 |
| Google Cloud Storage | gcs | GCS_CONNECTION_ID, GCS_BUCKET, GCS_PATH | ヘッダ行から推定 |
| Snowflake | snowflake | SNOWFLAKE_HOST, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA | TROCCO側で自動取得 |
| Google Analytics 4 | google_analytics4 | GA4_CONNECTION_ID | 定型レポートフィールド |
| Google Ads | google_ads | GADS_CONNECTION_ID | 定型レポートフィールド |
| HTTP (API) | http | HTTP_URL, HTTP_METHOD | レスポンスJSONから推定 |
| SFTP | sftp | SFTP_CONNECTION_ID, SFTP_PATH | ヘッダ行から推定 |
| Databricks | databricks | DB_HOST, DB_HTTP_PATH, DB_TOKEN, DB_CATALOG, DB_SCHEMA | TROCCO側で自動取得 |
| HubSpot | hubspot | HUBSPOT_CONNECTION_ID | TROCCO側で自動取得 |

## デスティネーション（転送先）

| コネクタ名 | Terraform output_option_type | Exampleあり | 備考 |
|-----------|----------------------------|-------------|------|
| BigQuery | bigquery | Yes | 最も実績あり。推奨デスティネーション |
| Snowflake | snowflake | **No** | スキーマ上存在するがexampleなし。問題発生時はREST APIフォールバック |
| MySQL | mysql | Yes | |
| PostgreSQL | postgresql | Yes | |
| Salesforce | salesforce | Yes | |
| Google Spreadsheets | google_spreadsheets | Yes | |
| kintone | kintone | Yes | |
| Databricks | databricks | Yes | |
| SFTP | sftp | Yes | |

## Terraform Provider 情報

- **Provider:** `trocco-io/trocco`
- **推奨バージョン:** `~> 0.24`
- **Terraform本体:** `>= 1.5.0`
- **リポジトリ:** https://github.com/trocco-io/terraform-provider-trocco
- **Terraform Registry:** https://registry.terraform.io/providers/trocco-io/trocco/latest
- **リージョン値:** `"japan"`, `"india"`, `"korea"`（v0.24で `"jp"` 等は廃止）
- **接続リソース:** `trocco_connection` の属性はフラット構造（ネストブロック不使用）

## TROCCO API 情報

- **ベースURL:** `https://trocco.io/api`
- **認証:** `Authorization: Token <TROCCO_API_KEY>`
- **レート制限:** 3,500 calls/10min（Advanced以上のプランで利用可能）
- **APIドキュメント:** https://documents.trocco.io/apidocs

### 主要エンドポイント

| メソッド | エンドポイント | 用途 |
|---------|-------------|------|
| GET | /api/connections/{connection_type} | 接続情報一覧取得 |
| GET | /api/connections/{connection_type}/{id} | 接続情報詳細取得 |
| GET | /api/job_definitions | ジョブ定義一覧取得 |
| POST | /api/job_definitions | ジョブ定義作成 |
| POST | /api/jobs?job_definition_id={id} | ジョブ実行 |
| GET | /api/jobs/{id} | ジョブ実行結果取得（※1） |

> **※1 ジョブ実行結果取得API (`GET /api/jobs/{id}`) について:**
> - APIキーに「転送ジョブの閲覧」権限が必要
> - `"Not Authorized"` が返る場合はTROCCO管理画面でAPIキーの権限設定を確認
> - status値: `queued`, `setting_up`, `executing`, `interrupting`, `succeeded`, `error`, `canceled`, `skipped`
> - APIリファレンス: https://documents.trocco.io/apidocs/get-job

> **接続情報一覧API仕様:**
> - `connection_type` はパスパラメータ（クエリパラメータではない）
> - クエリパラメータ: `limit`（最大200、デフォルト50）、`cursor`（ページネーション）
> - レスポンス: `items[]` 配列（各要素に `id`, `name`, `description` 等）
> ```bash
> curl -s "https://trocco.io/api/connections/kintone" \
>   -H "Authorization: Token ${TROCCO_API_KEY}" \
>   | jq '.items[] | {id, name}'
> ```
> 参照: https://documents.trocco.io/apidocs/get-connection-configurations
>
> **注意:** 接続情報一覧APIはAPIキーの権限スコープに「接続情報の閲覧」が
> 含まれている必要があります。`"Not Authorized"` エラーが返る場合は、
> TROCCO管理画面でAPIキーの権限設定を確認してください。
> 接続IDが既知の場合は、`.env.local` に直接設定することでこのAPIの
> 呼び出しをスキップできます。

## Snowflake デスティネーションのフォールバック手順

Terraform Provider 経由で `snowflake_output_option` にエラーが出た場合:

1. terraform plan のエラーメッセージを確認
2. `snowflake_output_option` のパラメータに問題がある場合、TROCCO REST APIで直接作成:

```bash
source .env.local
curl -s -X POST "https://trocco.io/api/job_definitions" \
  -H "Authorization: Token ${TROCCO_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{job_name}",
    "input_option_type": "kintone",
    "input_option": { ... },
    "output_option_type": "snowflake",
    "output_option": {
      "snowflake_connection_id": {connection_id},
      "warehouse": "{warehouse}",
      "database": "{database}",
      "schema": "{schema}",
      "table": "{table}",
      "mode": "replace"
    },
    "filter_columns": [ ... ]
  }'
```

3. APIドキュメント: https://documents.trocco.io/apidocs/post-job-definition
4. Snowflake転送先仕様: https://documents.trocco.io/docs/en/data-destination-snowflake
