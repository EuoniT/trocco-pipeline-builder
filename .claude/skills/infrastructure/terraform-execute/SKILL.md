---
name: terraform-execute
description: Terraform plan/applyの実行・エラーハンドリング・ユーザー承認を管理する
---

# Terraform Plan/Apply 共通手順

オーケストレーター (`setup-pipeline.md`) から呼び出される共通手順。
ソース・デスティネーションSkillから渡される情報をもとに terraform plan/apply を実行する。

## 1. TF_VAR_xxx 環境変数の export

ソース・デスティネーションSkillで定義された「TF_VAR export パターン」に従い、
`.env.local` から読み込んだ値を Terraform 変数として export する。

**共通 (全パイプライン):**
```bash
set -a; source ../../.env.local; set +a
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"
```

**ソース固有/デスティネーション固有:**
各Skillの「TF_VAR export パターン」セクションを参照し、必要な変数を export する。

## 2. terraform init & plan

```bash
cd pipelines/{pipeline-name}
bash -c '
set -a; source ../../.env.local; set +a

# Common
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# --- ソースSkill / デスティネーションSkillで定義されたTF_VAR export をここに挿入 ---

terraform init && terraform plan -out=tfplan
' 2>&1 | tee /tmp/terraform-plan-output.txt
```

## 3. plan 結果の提示

**必ず plan の結果をユーザーに以下の形式で提示:**
- 作成されるリソース数（例: "3 to add, 0 to change, 0 to destroy"）
- 各リソースの概要（Connection名/タイプ、Job Definition名、転送カラム数）

## 4. plan エラー時の対応

plan にエラーがある場合:
1. エラーメッセージを解析
2. HCLを修正して再実行（最大3回まで）
3. 3回失敗した場合はエラー内容をユーザーに報告して停止

**Snowflake デスティネーションの場合:**
plan失敗時は `reference/destinations/snowflake.md` の REST API フォールバック手順を実行する。

## 5. --dry-run チェック

`--dry-run` が指定されている場合はここで停止し、plan結果のみを報告する。

## 6. terraform apply（ユーザー承認後のみ）

**重要: ユーザーが明示的に「apply」「実行」「OK」等と承認した場合のみ実行すること。**

```bash
cd pipelines/{pipeline-name}
bash -c '
set -a; source ../../.env.local; set +a

# Common
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# --- ソースSkill / デスティネーションSkillで定義されたTF_VAR export をここに挿入 ---

terraform apply tfplan
' 2>&1 | tee /tmp/terraform-apply-output.txt
```

apply結果を確認し、作成されたリソースIDを記録する。

## 7. apply 失敗時の対応

apply が失敗した場合:
1. エラー内容を表示
2. `terraform destroy` でのロールバックを提案
3. ユーザーの承認を得てから destroy を実行
