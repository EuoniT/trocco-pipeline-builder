# TROCCO Pipeline Builder

> 自然言語から TROCCO データパイプラインを構築する Claude Code スキル

`kintone to Snowflake` のようなコマンドを解析し、Terraform HCL を自動生成して TROCCO のデータ転送パイプラインをデプロイします。**プログラミング不要** — Markdown プロンプトと宣言的な HCL だけで完結します。

> **Note:** 2025/02/10 現在、動作確認済みの組み合わせは **kintone → BigQuery** のみです。その他のコネクタは実験的サポートです。

## 免責事項

本プロジェクトは個人による非公式のオープンソースプロジェクトであり、[TROCCO](https://trocco.io)（株式会社 primeNumber）、[kintone](https://kintone.dev/)（サイボウズ株式会社）、[Snowflake](https://www.snowflake.com/)、[Google Cloud](https://cloud.google.com/)、および [Anthropic](https://www.anthropic.com/) とは一切関係がありません。各製品名・サービス名はそれぞれの企業の商標または登録商標です。

## 仕組み

```
/setup-pipeline kintone to Snowflake
```

1. 自然言語入力を解析（ソース → デスティネーション）
2. ソーススキーマを API 経由で取得（例: kintone フォームフィールド取得 API）
3. フィールド型を TROCCO カラム型に自動マッピング
4. Terraform HCL を生成（コネクション＋ジョブ定義）
5. `terraform plan` → ユーザー確認 → `terraform apply`
6. TROCCO API 経由でテスト実行 → 結果レポート

## クイックスタート

### 前提条件

| ツール | バージョン | インストール |
|--------|-----------|-------------|
| [Claude Code](https://claude.ai/code) | 最新 | ドキュメント参照 |
| [Terraform](https://www.terraform.io/) | >= 1.5.0 | `brew install terraform` |
| [jq](https://jqlang.github.io/jq/) | 最新 | `brew install jq` |
| [TROCCO](https://trocco.io) アカウント | Advanced+ | API アクセスが必要 |

### セットアップ

```bash
git clone https://github.com/kentayamamoto/trocco-pipeline-builder.git
cd trocco-pipeline-builder
cp .env.example .env.local
# .env.local を編集して認証情報を設定
```

### 実行

```bash
# パイプラインを構築:
/setup-pipeline kintone to Snowflake

# ドライランモード（plan のみ、apply なし）:
/setup-pipeline kintone to Snowflake --dry-run

# 日本語の自然言語にも対応:
/setup-pipeline kintoneの顧客管理アプリをSnowflakeに毎日転送して
```

## 対応コネクタ

### ソース（入力元）

kintone, MySQL, PostgreSQL, BigQuery, Salesforce, Google Spreadsheets, S3, GCS, Snowflake, HTTP, Google Analytics 4, Google Ads, SFTP, Databricks, HubSpot

### デスティネーション（出力先）

BigQuery, Snowflake\*, MySQL, PostgreSQL, Salesforce, Google Spreadsheets, kintone, Databricks, SFTP

\*Snowflake: Terraform Provider 経由（REST API フォールバック付き）

詳細は [reference/connector-catalog.md](reference/connector-catalog.md) を参照してください。

## デモ環境の構築

無料アカウントで試す手順：

1. **kintone 開発者ライセンス**（無料・1年間）: [登録はこちら](https://kintone.dev/en/developer-license-registration-form/)
   - テンプレートから「顧客管理」アプリを作成
   - 読み取り権限付きの API トークンを発行
2. **Snowflake フリートライアル**（30日間・$400 クレジット）: [登録はこちら](https://signup.snowflake.com/)
   - `DEMO_DB.PUBLIC` スキーマを作成
3. `.env.local` に認証情報を設定
4. 実行: `/setup-pipeline kintone to Snowflake`

## プロジェクト構成

```
.claude/commands/
  setup-pipeline.md          # スキルのエントリポイント（/setup-pipeline）
reference/
  connector-catalog.md       # 対応コネクタ一覧と TROCCO API 情報
  type-mapping.md            # kintone → TROCCO カラム型変換テーブル
  terraform-patterns.md      # HCL 生成ルールとテンプレート
  sources/kintone.md         # kintone ソースリファレンス
  destinations/bigquery.md   # BigQuery デスティネーションリファレンス
  destinations/snowflake.md  # Snowflake デスティネーションリファレンス
examples/
  kintone-to-bigquery/       # 参考 HCL: kintone → BigQuery
  kintone-to-snowflake/      # 参考 HCL: kintone → Snowflake
docs/
  architecture.md            # 技術設計概要
pipelines/                   # terraform apply で自動生成（gitignore 対象）
```

## セキュリティ

- すべての認証情報は `.env.local` に格納（gitignore 対象）
- Terraform の sensitive 変数は `TF_VAR_xxx` 環境変数で注入
- `terraform apply` にはユーザーの明示的な承認が必要
- kintone のレコードデータは取得しない（フィールド定義のみ）
- `terraform.tfstate` は gitignore 対象

## 新しいコネクタの追加

1. `reference/sources/{connector}.md` または `reference/destinations/{connector}.md` を作成
2. `reference/connector-catalog.md` にエントリを追加
3. `setup-pipeline.md` の変更は不要

詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## アーキテクチャ

技術設計の詳細は [docs/architecture.md](docs/architecture.md) を参照してください。

## コントリビューション

[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

Apache License 2.0 — [LICENSE](LICENSE) を参照してください。

## 参考リンク

- [TROCCO API ドキュメント](https://documents.trocco.io/apidocs)
- [TROCCO Terraform Provider](https://registry.terraform.io/providers/trocco-io/trocco/latest)
- [kintone REST API](https://kintone.dev/en/docs/kintone/rest-api/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
