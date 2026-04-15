# Snowflake → Salesforce パイプライン例

## 概要

Snowflake のテーブルまたはカスタムクエリからデータを取得し、Salesforce オブジェクトに転送するパイプラインの参考実装。
テーブル指定とカスタム SQL クエリの両方をサポート。

## 接続モード

- **Snowflake Source:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password / key_pair 認証）
- **Salesforce Dest:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password 認証）

## 注意事項

- **`input_option_columns` を使用:** Snowflake ソースは `input_option_columns`（name + type）を使用。Salesforce ソースの `columns` とは異なるので注意
- **`query` を使用:** テーブル全体を取得する場合は `SELECT * FROM table_name` を指定
- **Private Key Format:** `.env.local` で秘密鍵の改行を `\n` リテラルで記載し、`printf '%b'` で変換
- **プレフィックス規則:** ソース Snowflake は `SNOWFLAKE_SRC_*`、デスティネーション Snowflake（別パイプラインの場合）は `SNOWFLAKE_*`
- **Sandbox 対応:** `salesforce_dest_auth_end_point` を `https://test.salesforce.com/services/Soap/u/` に変更

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# Snowflake Source: 共通変数（input_option 用 — 両モード必須）
export TF_VAR_snowflake_src_database="$SNOWFLAKE_SRC_DATABASE"
export TF_VAR_snowflake_src_schema="$SNOWFLAKE_SRC_SCHEMA"
export TF_VAR_snowflake_src_warehouse="$SNOWFLAKE_SRC_WAREHOUSE"
export TF_VAR_snowflake_src_role="$SNOWFLAKE_SRC_ROLE"
export TF_VAR_snowflake_src_query="$SNOWFLAKE_SRC_QUERY"

# Snowflake Source: 接続情報（モードに応じて分岐）
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

# Salesforce Dest: 共通変数（output_option 用 — 両モード必須）
export TF_VAR_salesforce_dest_object_name="$SALESFORCE_DEST_OBJECT_NAME"
[ -n "$SALESFORCE_DEST_ACTION_TYPE" ] && export TF_VAR_salesforce_dest_action_type="$SALESFORCE_DEST_ACTION_TYPE"
[ -n "$SALESFORCE_DEST_UPSERT_KEY" ] && export TF_VAR_salesforce_dest_upsert_key="$SALESFORCE_DEST_UPSERT_KEY"
[ -n "$SALESFORCE_DEST_API_VERSION" ] && export TF_VAR_salesforce_dest_api_version="$SALESFORCE_DEST_API_VERSION"

# Salesforce Dest: 接続情報（モードに応じて分岐）
if [ -n "$SALESFORCE_DEST_CONNECTION_ID" ]; then
  export TF_VAR_salesforce_dest_connection_id="$SALESFORCE_DEST_CONNECTION_ID"  # モードA
else
  export TF_VAR_salesforce_dest_username="$SALESFORCE_DEST_USERNAME"
  export TF_VAR_salesforce_dest_password="$SALESFORCE_DEST_PASSWORD"
  export TF_VAR_salesforce_dest_security_token="$SALESFORCE_DEST_SECURITY_TOKEN"
  [ -n "$SALESFORCE_DEST_AUTH_END_POINT" ] && export TF_VAR_salesforce_dest_auth_end_point="$SALESFORCE_DEST_AUTH_END_POINT"
fi

terraform plan -out=tfplan
```

## 関連ドキュメント

- ソース: `reference/sources/snowflake/README.md`
- デスティネーション: `reference/destinations/salesforce/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
