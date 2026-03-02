# kintone → Snowflake パイプライン例

## 概要

kintone アプリのデータを Snowflake に転送するパイプラインの参考実装。

## 接続モード

- **kintone:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、token認証）
- **Snowflake:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password / key_pair 認証）

## 注意事項

- Snowflake `snowflake_output_option` は Terraform Provider に公式 example がないため、plan 時エラーが発生する可能性がある
- エラー時は TROCCO REST API フォールバックを使用（`reference/destinations/snowflake/README.md` 参照）
- kintone のレコードデータは直接取得しない（フィールド定義のみ Get Form Fields API で取得）

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# kintone: モードに応じて注入
[ -n "$KINTONE_CONNECTION_ID" ] && export TF_VAR_kintone_connection_id="$KINTONE_CONNECTION_ID"
[ -z "$KINTONE_CONNECTION_ID" ] && export TF_VAR_kintone_api_token="$KINTONE_API_TOKEN"

# Snowflake共通変数（output_option 用 — 両モード必須）
export TF_VAR_snowflake_warehouse="$SNOWFLAKE_WAREHOUSE"
export TF_VAR_snowflake_database="$SNOWFLAKE_DATABASE"
[ -n "$SNOWFLAKE_SCHEMA" ] && export TF_VAR_snowflake_schema="$SNOWFLAKE_SCHEMA"
[ -n "$SNOWFLAKE_TABLE" ] && export TF_VAR_snowflake_table="$SNOWFLAKE_TABLE"
export TF_VAR_snowflake_role="$SNOWFLAKE_ROLE"

# Snowflake接続情報（モードに応じて分岐）
if [ -z "$SNOWFLAKE_CONNECTION_ID" ]; then
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

- ソース: `reference/sources/kintone/README.md`
- デスティネーション: `reference/destinations/snowflake/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
