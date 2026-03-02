---
name: generate-env
description: パイプラインの組み合わせに応じた .env.local テンプレートを生成する。例: "kintone to Snowflake"
argument-hint: "[source] to [destination]"
---

# Generate Env Skill

ユーザーが指定したソース/デスティネーションの組み合わせに必要な環境変数のみを含む `.env.local` テンプレートを自動生成する。

## 入力パース

ユーザー入力: `$ARGUMENTS`

以下を解析:
1. **ソース（転送元）**: "to" の前の部分（例: "kintone", "google spreadsheets"）
2. **デスティネーション（転送先）**: "to" の後の部分（例: "Snowflake", "BigQuery"）

ソース名を正規化（スペースはアンダースコアに、小文字化）:
- "kintone" → `kintone`
- "google spreadsheets" / "Google Spreadsheets" → `google_spreadsheets`

デスティネーション名を正規化:
- "BigQuery" / "bigquery" → `bigquery`
- "Snowflake" / "snowflake" → `snowflake`

## 実行フロー

### 1. コネクタ対応確認

Glob で以下の SKILL ファイルの存在を確認し、指定されたソース/デスティネーションが対応しているか確認する:
- `.claude/skills/sources/{src}/SKILL.md`
- `.claude/skills/destinations/{dest}/SKILL.md`

SKILL ファイルが存在しない場合は「未対応のコネクタです」と案内して停止。

### 2. env-vars.json の読み込み

以下の3ファイルを Read で読み込み、JSON をパースする:
- `.claude/skills/infrastructure/generate-env/env-vars.json` — common 部分（TROCCO_API_KEY 等）
- `reference/sources/{src}/env-vars.json` — 指定ソースの変数
- `reference/destinations/{dest}/env-vars.json` — 指定デスティネーションの変数

### 3. 必要セクションの抽出

読み込んだ3つのJSONファイルから変数定義を抽出する:
- `common` — `.claude/skills/infrastructure/generate-env/env-vars.json` の `common` セクション
- ソース — `reference/sources/{src}/env-vars.json` 全体
- デスティネーション — `reference/destinations/{dest}/env-vars.json` 全体

### 4. .env.local テンプレートの整形

以下のフォーマットでテンプレートを組み立てる:

```
# TROCCO Pipeline Builder 環境変数テンプレート
# Generated for: {SourceDisplayName} -> {DestDisplayName}
#
# このファイルは自動生成されました。各変数に適切な値を設定してください。

# === {common.description} ===
# {variable.description}
VARIABLE_NAME="example_value"

# --- {SourceDisplayName} ソース ---
# {source.description}
# [A] 既存接続を使う（推奨）:
#   {mode_a.description}
SOURCE_CONNECTION_ID=""
# [B] Terraformで新規作成:
#   {mode_b.description}
SOURCE_FIELD=""
# 共通:
# {always_var.description}
SOURCE_ALWAYS_VAR="example"

# --- {DestDisplayName} デスティネーション ---
# （同様の形式で出力）
```

**整形ルール:**
- 各変数の `description` があればコメント行 `# {description}` を変数の直前に出力
- modes がある場合: `# [{mode_key大文字}] {label}:` + `#   {description}` のヘッダー付きで変数を出力
- `always` 配列がある場合: modes の後に `# 共通:` ヘッダーで出力
- 各変数は `NAME="example"` の形式（example は env-vars.json の `example` フィールドの値）
- セクション間は空行で区切る

### 5. 既存ファイル確認

Glob で `.env.local` の存在を確認する。

- `.env.local` が **存在しない** 場合: そのまま Step 6 へ
- `.env.local` が **存在する** 場合: ユーザーに上書きの確認を取る
  - 承認 → Step 6 へ
  - 拒否 → 停止

### 6. ファイル出力

Write ツールで `.env.local` にテンプレートを書き出す。

### 7. 結果表示と案内

生成されたテンプレートの内容を表示し、以下を案内:

1. `.env.local` の各変数に適切な値を設定してください
2. モードA/Bの説明:
   - **モードA（既存接続）**: TROCCO管理画面で接続を事前に作成し、そのIDを設定（推奨）
   - **モードB（Terraform新規作成）**: 接続IDを空にし、認証情報を直接設定
3. 設定完了後、`/setup-pipeline {src} to {dest}` でパイプライン構築を実行できます
