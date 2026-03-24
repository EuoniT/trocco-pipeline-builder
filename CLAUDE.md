# TROCCO Pipeline Builder

自然言語から TROCCO データパイプラインを構築する Claude Code プロジェクト。
Markdown プロンプト + Terraform HCL のみで完結（プログラミング不要）。

## コマンド

| コマンド | 説明 |
|---------|------|
| `/setup-pipeline [source] to [dest]` | パイプラインの自律構築 |
| `/setup-pipeline [source] to [dest] --dry-run` | plan のみ（apply なし） |
| `/generate-env [source] to [dest]` | `.env.local` テンプレート生成 |

## プロジェクト構造

```
.claude/
  commands/setup-pipeline.md              # オーケストレーター（/setup-pipeline）
  skills/
    sources/{connector}/SKILL.md          # ソース Skill（kintone, google_spreadsheets）
    sources/_template.md                  # 新規ソース Skill テンプレート
    destinations/{connector}/SKILL.md     # デスティネーション Skill（bigquery, snowflake）
    destinations/_template.md             # 新規デスティネーション Skill テンプレート
    infrastructure/                       # 共通 Skill
      env-check/SKILL.md                 #   環境チェック
      terraform-execute/SKILL.md         #   Terraform plan/apply
      test-and-report/SKILL.md           #   テスト実行・結果レポート
      generate-env/                      #   .env.local テンプレート生成
        SKILL.md / env-vars.json
reference/
  connector-catalog.md                    # 対応コネクタ一覧・TROCCO API 情報
  type-mapping.md                         # フィールド型変換表
  terraform-patterns.md                   # HCL 生成ルール・テンプレート
  sources/{connector}.md                  # ソースリファレンス
  destinations/{connector}.md             # デスティネーションリファレンス
examples/{source}-to-{dest}/              # 参考 HCL 実装
docs/architecture.md                      # アーキテクチャ詳細
pipelines/                                # terraform apply で自動生成（gitignored）
```

## セキュリティルール（厳守）

- 機密情報は `.env.local` からのみ読み込む（HCL にハードコードしない）
- `terraform.tfvars` に機密値を書かない（`tfvars > env vars` の優先順位により、空文字でも `TF_VAR_xxx` を上書きする）
- `terraform apply` は必ずユーザー承認後に実行
- `terraform.tfstate` を git にコミットしない
- kintone のレコードデータは取得しない（フィールド定義のみ）

## HCL 生成ルール

- `required_version = ">= 1.5.0"`
- Provider: `trocco-io/trocco` version `~> 0.24`
- `labels` は使用しない（TROCCO で事前登録済みのラベル名のみ受け付けるため）
- 詳細は `reference/terraform-patterns.md` を参照

## 環境変数

- `.env.local` に設定（テンプレート: `.env.example`）
- 各コネクタの必要変数は Skill ファイルの「必要環境変数」セクションを参照
- 変数定義一覧: `.claude/skills/infrastructure/generate-env/env-vars.json`

## 拡張方法

新コネクタ追加は `docs/architecture.md`「Adding a New Connector」セクション参照。
オーケストレーター変更不要（Glob による動的 Skill 検出）。
