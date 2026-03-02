# Google Spreadsheets → Snowflake パイプライン例

## 概要

Google Spreadsheets のデータを Snowflake に転送するパイプラインの参考実装。

## 接続モード

- **Google Spreadsheets:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、サービスアカウント認証）
- **Snowflake:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password / key_pair 認証）

## 注意事項

- Google Spreadsheets にはフォーマルな型定義がないため、サンプルデータからの推論で型を決定
- Snowflake `snowflake_output_option` は Terraform Provider に公式 example がないため、plan 時エラーが発生する可能性がある
- エラー時は TROCCO REST API フォールバックを使用（`reference/destinations/snowflake/README.md` 参照）

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# GS接続: モードに応じて注入
if [ -n "$GS_CONNECTION_ID" ]; then
  export TF_VAR_gs_connection_id="$GS_CONNECTION_ID"  # モードA
else
  export TF_VAR_gs_service_account_json_key="$GS_SERVICE_ACCOUNT_JSON_KEY"  # モードB
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

- ソース: `reference/sources/google_spreadsheets/README.md`
- デスティネーション: `reference/destinations/snowflake/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
