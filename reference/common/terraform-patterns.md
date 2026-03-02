# Terraform HCL 生成パターン

## ディレクトリ構造

```
pipelines/{source}-to-{dest}-{YYYYMMDD-HHMMSS}/
├── main.tf              # Provider + Connection + Job Definition
├── variables.tf         # 変数定義
├── outputs.tf           # 出力定義
├── terraform.tfvars     # 変数値（.gitignore対象）
└── README.md            # 自動生成サマリ
```

## リソース命名規則

### Connection
- ソース: `trocco_connection.{source_type}_source` （例: `trocco_connection.kintone_source`）
- デスティネーション: `trocco_connection.{dest_type}_dest` （例: `trocco_connection.snowflake_dest`）

### Job Definition
- リソース名: `trocco_job_definition.{source_type}_to_{dest_type}` （例: `trocco_job_definition.kintone_to_snowflake`）
- ジョブ名（name属性）: `{source_name}-to-{dest_name}-{table_name}` （例: `kintone-顧客管理-to-snowflake`）

## mode の選択基準

| ユースケース | mode | 備考 |
|-------------|------|------|
| 初回転送・全件洗い替え | replace | テーブルをDROP→CREATE→INSERT |
| 差分追記 | insert | 既存データを残して追記 |
| 全件削除→挿入 | truncate_insert | TRUNCATE→INSERT |
| 主キーでマージ | merge | merge_keys の指定が必須 |
| 直接INSERT | insert_direct | Snowflake固有（ステージング不使用） |

デフォルト: `replace`（初回・デモ用途に最適）

## 接続情報の2モード対応

全てのコネクタで「既存接続ID参照」と「Terraform新規作成」の2モードをサポート:

| モード | 条件 | 動作 |
|--------|------|------|
| A（推奨） | `*_CONNECTION_ID` が設定済み | 既存接続をIDで参照。`trocco_connection` リソース作成をスキップ |
| B | `*_CONNECTION_ID` が空/null | `trocco_connection` リソースをTerraformで新規作成 |

HCLでの実装パターン:
```hcl
variable "kintone_connection_id" {
  type    = number
  default = null  # null = モードB（新規作成）
}

resource "trocco_connection" "kintone_source" {
  count = var.kintone_connection_id == null ? 1 : 0
  # ...
}

locals {
  kintone_connection_id = (
    var.kintone_connection_id != null
    ? var.kintone_connection_id
    : trocco_connection.kintone_source[0].id
  )
}
```

## 機密情報の取り扱い

⚠ **重要: Terraform の変数優先順位は tfvars > 環境変数。**
sensitive値をtfvarsに空文字で書くと、TF_VAR_xxx環境変数が上書きされるため、
**sensitive値はtfvarsに一切書かない。**

sensitive変数は terraform.tfvars に書かず、環境変数のみで注入する:

```bash
source .env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# モードに応じて接続情報を注入（各コネクタの SKILL.md / README.md に記載のパターンに従う）
# モードA: 既存接続ID参照
[ -n "$XXX_CONNECTION_ID" ] && export TF_VAR_xxx_connection_id="$XXX_CONNECTION_ID"

# モードB: Terraform新規作成（接続IDが空の場合のみ必要）
[ -z "$XXX_CONNECTION_ID" ] && export TF_VAR_xxx_auth_field="$XXX_AUTH_FIELD"

terraform plan -out=tfplan
```

terraform.tfvars にはsensitive値を書かない。コメントで環境変数注入を案内:
```hcl
# trocco_api_key → TF_VAR_trocco_api_key で注入（tfvarsに書くとenv varが上書きされる）
# 各コネクタの sensitive 変数 → 対応する TF_VAR_xxx で注入
```
