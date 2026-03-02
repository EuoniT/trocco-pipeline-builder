# kintone → BigQuery パイプライン例

## 概要

kintone アプリのデータを BigQuery に転送するパイプラインの参考実装。
BigQuery は Phase 1 の推奨デスティネーション。Terraform Provider に公式 example あり。

## 接続モード

- **kintone:** Mode A（既存接続ID参照）/ Mode B（Terraform新規作成、token認証）
- **BigQuery:** TROCCO UI で作成した接続を `bq_connection_id` で参照（Terraform での接続新規作成は非対応）

## 注意事項

- BigQuery 接続は TROCCO UI で事前に作成し、`bq_connection_id` で参照する
- `location` のデフォルトは `"US"`。日本リージョンを使う場合は `"asia-northeast1"` を明示的に設定
- kintone のレコードデータは直接取得しない（フィールド定義のみ Get Form Fields API で取得）

## 機密情報の注入

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# kintone: モードに応じて注入
if [ -n "$KINTONE_CONNECTION_ID" ]; then
  export TF_VAR_kintone_connection_id="$KINTONE_CONNECTION_ID"  # モードA
else
  export TF_VAR_kintone_api_token="$KINTONE_API_TOKEN"          # モードB
fi

terraform plan -out=tfplan
```

※ BigQuery は TROCCO 接続IDで参照するため、追加の TF_VAR 注入は不要

## 関連ドキュメント

- ソース: `reference/sources/kintone/README.md`
- デスティネーション: `reference/destinations/bigquery/README.md`
- 共通パターン: `reference/common/terraform-patterns.md`
