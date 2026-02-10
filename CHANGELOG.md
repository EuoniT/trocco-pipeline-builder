# 変更履歴

このプロジェクトの主な変更点をすべて記録します。

## [Unreleased]

### 追加

- 初回リリース
- `/setup-pipeline` Claude Code スキル
- kintone ソースサポート（フォームフィールド取得 API 連携）
- Snowflake デスティネーションサポート（Terraform + REST API フォールバック）
- BigQuery デスティネーションサポート
- リファレンスドキュメント: connector-catalog, type-mapping, terraform-patterns
- 個別コネクタリファレンス: `reference/sources/kintone.md`, `reference/destinations/bigquery.md`, `reference/destinations/snowflake.md`
- サンプル HCL: kintone-to-snowflake, kintone-to-bigquery
- `--dry-run` モード（plan のみ）
- フィールド型の自動マッピング（kintone → TROCCO カラム型）
- 日本語フィールド名 → 英語 snake_case 変換
- Apache License 2.0
