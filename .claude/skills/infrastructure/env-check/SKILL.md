---
name: env-check
description: Terraform/jq/環境変数の存在チェックを実行する
---

# 環境チェック共通手順

オーケストレーター (`setup-pipeline.md`) から呼び出される共通手順。
ソース・デスティネーションのSkillが定義する必要環境変数を動的にチェックする。

## 1. ツールチェック

以下のコマンドをBashツールで実行して環境を確認:

```bash
# 1. Terraform v1.5以上が必要
terraform version

# 2. jq インストール確認
which jq
```

- Terraform が未インストール or v1.5未満 → インストール案内して停止
- jq が未インストール → インストール案内して停止

## 2. .env.local の読み込み

```bash
if [ -f .env.local ]; then
  set -a && source .env.local && set +a
  echo ".env.local loaded"
else
  echo ".env.local not found"
fi
```

- `.env.local` が存在しない → テンプレート生成を案内:
  `/generate-env {src} to {dest}` でテンプレートを生成できることを案内して停止

## 3. TROCCO_API_KEY チェック (必須)

```bash
set -a && source .env.local && set +a
echo "TROCCO_API_KEY: ${TROCCO_API_KEY:+configured}"
```

- `TROCCO_API_KEY` が未設定 → `.env.local` に設定を求めて停止

## 4. ソース/デスティネーション固有の環境変数チェック

ソースSkillとデスティネーションSkillの「必要環境変数」セクションに記載された変数を動的にチェックする。

チェック対象は、オーケストレーターから渡されるソース・デスティネーションの種類に応じて判定:

- **ソース固有変数:** ソースSkill (`.claude/skills/sources/{src}/SKILL.md`) の「必要環境変数」セクション参照
- **デスティネーション固有変数:** デスティネーションSkill (`.claude/skills/destinations/{dest}/SKILL.md`) の「必要環境変数」セクション参照

各変数の設定状況を表示し、不足がある場合は以下を案内して停止する:
`/generate-env {src} to {dest}` で必要な変数テンプレートを生成し、`.env.local` に値を設定してから再実行。

### チェック時の注意

- 2モード対応コネクタ（kintone, Google Spreadsheets, Snowflake）では、モードA/Bの判定も行う
- モードA（既存接続ID参照）の場合は接続作成用の変数（domain, token等）は不要
- モードB（Terraform新規作成）の場合は接続IDは不要だが、認証情報が必須
