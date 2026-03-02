# Amazon S3 → Snowflake パイプライン例

## 概要

Amazon S3 のファイルデータを Snowflake に転送するパイプラインの参考実装。
この例は CSV パーサーを使用。他のパーサー（JSONL, Parquet, Excel 等）の場合は `csv_parser` を対応するパーサーに置換する。

## 接続モード

- **Amazon S3:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、IAM User / AssumeRole 認証）
- **Snowflake:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、user_password / key_pair 認証）

## 注意事項

- **パーサー選択:** Terraform の条件分岐は使わない。ファイル形式は HCL 生成時に確定しているため、選択されたパーサーのブロックのみ生成する
- **decoder は必須:** 省略すると "Provider produced inconsistent result" エラー。`{ match_name = "" }` を必ず指定
- **Provider 互換性:** `aws_assume_role = ... : null` の三項演算子パターンは Provider エラーを引き起こす。`aws_auth_type` に応じて使用する認証ブロックのみ生成すること
- Snowflake `snowflake_output_option` は plan 時エラーが発生する可能性がある。エラー時は REST API フォールバックを使用

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# S3接続: モードに応じて注入
if [ -n "$S3_CONNECTION_ID" ]; then
  export TF_VAR_s3_connection_id="$S3_CONNECTION_ID"  # モードA
else
  export TF_VAR_s3_aws_auth_type="${S3_AWS_AUTH_TYPE:-iam_user}"
  if [ "$S3_AWS_AUTH_TYPE" = "iam_user" ]; then
    export TF_VAR_s3_aws_access_key_id="$S3_AWS_ACCESS_KEY_ID"
    export TF_VAR_s3_aws_secret_access_key="$S3_AWS_SECRET_ACCESS_KEY"
  else
    export TF_VAR_s3_aws_account_id="$S3_AWS_ACCOUNT_ID"
    export TF_VAR_s3_aws_role_name="$S3_AWS_ROLE_NAME"
  fi
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

- ソース: `reference/sources/s3/README.md`
- デスティネーション: `reference/destinations/snowflake/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
