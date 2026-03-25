# Salesforce → Snowflake パイプライン例

## 概要

Salesforce のオブジェクトデータを Snowflake に転送するパイプラインの参考実装。
`object_acquisition_method = "all_columns"` でオブジェクトの全カラムを取得する例。SOQL を使用する場合は `object_acquisition_method = "soql"` に変更し、`soql` パラメータを追加する。

## 接続モード

- **Salesforce:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password 認証）
- **Snowflake:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password / key_pair 認証）

## 注意事項

- **`columns` を使用:** kintone/google_spreadsheets の `input_option_columns` ではなく、Salesforce は `columns` を使用（Provider仕様）
- **Sandbox 対応:** `salesforce_auth_end_point` を `https://test.salesforce.com/services/Soap/u/` に変更
- Snowflake `snowflake_output_option` は plan 時エラーが発生する可能性がある。エラー時は REST API フォールバックを使用

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# Salesforce接続: モードに応じて注入
if [ -n "$SALESFORCE_CONNECTION_ID" ]; then
  export TF_VAR_salesforce_connection_id="$SALESFORCE_CONNECTION_ID"  # モードA
else
  export TF_VAR_salesforce_username="$SALESFORCE_USERNAME"
  export TF_VAR_salesforce_password="$SALESFORCE_PASSWORD"
  export TF_VAR_salesforce_security_token="$SALESFORCE_SECURITY_TOKEN"
  [ -n "$SALESFORCE_AUTH_END_POINT" ] && export TF_VAR_salesforce_auth_end_point="$SALESFORCE_AUTH_END_POINT"
fi

# Snowflake共通変数（output_option 用 — 両モード必須）
export TF_VAR_snowflake_warehouse="$SNOWFLAKE_WAREHOUSE"
export TF_VAR_snowflake_database="$SNOWFLAKE_DATABASE"
[ -n "$SNOWFLAKE_SCHEMA" ] && export TF_VAR_snowflake_schema="$SNOWFLAKE_SCHEMA"
[ -n "$SNOWFLAKE_TABLE" ] && export TF_VAR_snowflake_table="$SNOWFLAKE_TABLE"
export TF_VAR_snowflake_role="$SNOWFLAKE_ROLE"

# Snowflake接続情報: モードに応じて注入
if [ -n "$SNOWFLAKE_CONNECTION_ID" ]; then
  export TF_VAR_snowflake_connection_id="$SNOWFLAKE_CONNECTION_ID"  # モードA
else
  export TF_VAR_snowflake_host="$SNOWFLAKE_HOST"
  export TF_VAR_snowflake_user="$SNOWFLAKE_USER"
  export TF_VAR_snowflake_auth_method="${SNOWFLAKE_AUTH_METHOD:-user_password}"
  if [ "$SNOWFLAKE_AUTH_METHOD" = "key_pair" ]; then
    export TF_VAR_snowflake_private_key="$(printf '%b' "$SNOWFLAKE_PRIVATE_KEY")"
  else
    export TF_VAR_snowflake_password="$SNOWFLAKE_PASSWORD"
  fi
fi

terraform plan -out=tfplan
```

## 関連ドキュメント

- ソース: `reference/sources/salesforce/README.md`
- デスティネーション: `reference/destinations/snowflake/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
