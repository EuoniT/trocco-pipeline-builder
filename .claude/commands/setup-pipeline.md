---
description: 自然言語入力からTROCCOパイプラインを自律構築する。TROCCO Terraform Provider活用。例: "kintone to Snowflake"
argument-hint: "[source] to [destination] [追加指示] [--dry-run]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Setup Pipeline Skill (Orchestrator)

あなたはTROCCOパイプライン構築の自律エージェントです。
ユーザーの自然言語入力を解析し、ソース/デスティネーション別のSkillファイルを読み込んで、データ転送パイプラインを自動構築します。

## 入力パース

ユーザー入力: `$ARGUMENTS`

以下を解析してください:
1. **ソース（転送元）**: 入力の "to" の前の部分（例: "kintone", "google spreadsheets"）
2. **デスティネーション（転送先）**: "to" の後の部分（例: "Snowflake", "BigQuery"）
3. **追加指示**: スケジュール、フィルタ条件、テーブル名等（あれば）
4. **--dry-run**: 指定されている場合は terraform plan までで停止

ソース名を正規化（スペースはアンダースコアに、小文字化）:
- "kintone" → `kintone`
- "google spreadsheets" / "Google Spreadsheets" → `google_spreadsheets`

デスティネーション名を正規化:
- "BigQuery" / "bigquery" → `bigquery`
- "Snowflake" / "snowflake" → `snowflake`

## リファレンス読み込み（必須）

処理を開始する前に、必ず以下のファイルをReadツールで読み込んでください:
- `reference/common/terraform-patterns.md` — HCL生成ルール・共通パターン
- `reference/common/trocco-api.md` — Provider・API情報

ソース/デスティネーションの対応確認はSKILLファイルのGlob検出で行います（Step 1-3 参照）。

## Skill選択・実行フロー

### Pre-Step: .env.local テンプレート生成

`.env.local` が存在しない場合、このパイプライン用のテンプレートを自動生成する。

```bash
[ -f .env.local ] && echo "EXISTS" || echo "NOT_FOUND"
```

- `.env.local` が存在しない場合:
  1. `.claude/skills/infrastructure/generate-env/SKILL.md` を Read で読み込み、手順に従ってテンプレートを生成
  2. ユーザーに各変数の設定を案内して **停止**
  3. 設定完了後に再度 `/setup-pipeline` を実行するよう案内
- `.env.local` が存在する場合: Step 0 へ進む

### Step 0: 環境チェック

`.claude/skills/infrastructure/env-check/SKILL.md` をReadで読み込み、手順に従って実行する。
ソース・デスティネーションの必要環境変数は、以下の各Skillファイルの「必要環境変数」セクションを参照。

### Step 1-3: ソースSkill実行

Globで `.claude/skills/sources/{src}/SKILL.md` の存在を確認し、Readで読み込む。
Skillファイルに従い以下を実行:
- Step 1: スキーマ/フィールド情報取得
- Step 2: フィールド→カラム型変換（type-mapping.md 適用）
- Step 3 (src): ソース接続確認

さらに、ソースの詳細リファレンスも読み込む:
- `reference/sources/{src}/README.md`（存在する場合）
- `reference/sources/{src}/type-mapping.md`（存在する場合 — フィールドタイプ変換表）

Skillファイルが存在しない場合は、ユーザーに「{src} ソースは未実装です」と伝えて停止。

### Step 3 (dest): デスティネーションSkill実行

Globで `.claude/skills/destinations/{dest}/SKILL.md` の存在を確認し、Readで読み込む。
Skillファイルに従いデスティネーション接続確認を実行。

さらに、デスティネーションの詳細リファレンスも読み込む:
- `reference/destinations/{dest}/README.md`（存在する場合）

Skillファイルが存在しない場合は、ユーザーに「{dest} デスティネーションは未実装です」と伝えて停止。

### Step 4: Terraform HCL 生成

`reference/common/terraform-patterns.md` のルールに従い、ソースSkill・デスティネーションSkillから取得した情報を統合してHCLを生成する。

ディレクトリ: `pipelines/{source}-to-{dest}-{YYYYMMDD-HHMMSS}/`

Writeツールで以下を生成:
1. `main.tf` — Provider設定 + Connection（ソースSkill/デスティネーションSkillのHCL情報を統合）+ Job Definition
2. `variables.tf` — 共通変数 + ソースSkillの変数 + デスティネーションSkillの変数（sensitive変数は `sensitive = true`）
3. `outputs.tf` — job_definition_id, connection_id, pipeline_summary
4. `terraform.tfvars` — 変数値（機密情報はtfvarsに書かない。TF_VAR_xxx環境変数で注入）

**HCL生成の重要ルール:**
- `required_version = ">= 1.5.0"` を必ず含める
- Provider: `trocco-io/trocco` version `~> 0.24`
- APIキー/パスワードをHCLにハードコードしない
- terraform.tfvars が `.gitignore` に含まれることを確認
- **`labels` は使用しない**（TROCCOで事前登録済みのラベル名のみ受け付けるため、自動生成では省略）

### Step 5-6: Terraform Plan/Apply

`.claude/skills/infrastructure/terraform-execute/SKILL.md` をReadで読み込み、手順に従って実行する。
ソースSkill・デスティネーションSkillの「TF_VAR export パターン」を統合して適用。

### Step 7-8: テスト実行・結果レポート

`.claude/skills/infrastructure/test-and-report/SKILL.md` をReadで読み込み、手順に従って実行する。

## エラーハンドリング

| エラー種別 | 検出方法 | 対処 |
|-----------|---------|------|
| kintone API認証エラー | HTTP 401/403 | 「KINTONE_API_TOKENを確認してください」と案内して停止 |
| kintone アプリ不存在 | HTTP 404 | 「KINTONE_APP_IDを確認してください」と案内して停止 |
| TROCCO API認証エラー | HTTP 401 | 「TROCCO_API_KEYを確認してください」と案内して停止 |
| TROCCO APIプラン不足 | HTTP 403 | 「APIアクセスにはAdvanced以上のプランが必要です」と案内 |
| TROCCO 接続一覧API権限エラー | HTTP 401/403 on `/api/connections/*` | 接続IDが .env.local に設定済みならスキップして続行。未設定なら「TROCCO管理画面 > 接続情報 でIDを確認し .env.local に設定してください」と案内 |
| terraform init失敗 | exit code != 0 | ネットワーク接続を確認。Providerバージョンを固定して再試行 |
| terraform plan失敗 | exit code != 0 | エラーメッセージを解析し、HCLを修正して再試行（最大3回） |
| terraform apply失敗 | exit code != 0 | エラー内容を表示し、`terraform destroy` でのロールバックを提案 |
| ジョブ実行失敗 | status = "error" | 「TROCCOの管理画面でジョブログを確認してください」と案内 |
| ジョブ結果API権限エラー | HTTP 401/403 on `GET /api/jobs/{id}` | ジョブ投入成功は伝えつつ、TROCCO管理画面で結果確認を案内。APIキーに「転送ジョブの閲覧」権限追加を推奨 |
| ラベル無効エラー | terraform apply で "invalid label included" | TROCCOでは事前登録済みのラベル名のみ使用可能。HCLから `labels` を除去して再apply |
| Snowflake output未対応 | plan時エラー | TROCCO REST API直接呼び出しにフォールバック（reference/destinations/snowflake/README.md参照） |
| ソースSkill未存在 | Globで検出なし | 「{src} ソースは未実装です」と案内して停止 |
| デスティネーションSkill未存在 | Globで検出なし | 「{dest} デスティネーションは未実装です」と案内して停止 |

## 安全性ルール

1. **terraform apply は必ずユーザー承認後のみ実行**
2. **機密情報（APIキー、パスワード）は `.env.local` から読み込み、HCLに直接書かない**
3. **terraform.tfvars が .gitignore に含まれていることを確認**
4. **terraform.tfstate をgitにコミットしない**
5. **既存リソースを変更・削除する場合は明示的に警告表示**
6. **`--dry-run` 指定時は plan までで停止**
7. **kintoneのレコードデータは取得しない（フィールド定義のみ取得）**

## bash + jq 実行時の注意事項

1. jqフィルタはシングルクォートで囲む（ダブルクォートだとbash変数展開と干渉する）
2. jqで不等号比較にはINパターンを使う: select(IN(.value.type; "A","B") | not)
3. jqはファイル引数で呼ぶ: jq '.filter' file.json（パイプ不要）
4. curl結果はHTTPステータス確認のため一旦変数に格納してからjqで処理する
5. echoとcurl/jqパイプを混在させない（echoを先に実行し、curl結果は変数格納後に処理）
