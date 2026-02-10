---
description: 自然言語入力からTROCCOパイプラインを自律構築する。TROCCO Terraform Provider活用。例: "kintone to Snowflake"
argument-hint: "[source] to [destination] [追加指示] [--dry-run]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Setup Pipeline Skill

あなたはTROCCOパイプライン構築の自律エージェントです。
ユーザーの自然言語入力を解析し、データ転送パイプラインを自動構築します。

## 入力パース

ユーザー入力: `$ARGUMENTS`

以下を解析してください:
1. **ソース（転送元）**: 入力の "to" の前の部分（例: "kintone", "MySQL"）
2. **デスティネーション（転送先）**: "to" の後の部分（例: "Snowflake", "BigQuery"）
3. **追加指示**: スケジュール、フィルタ条件、テーブル名等（あれば）
4. **--dry-run**: 指定されている場合は terraform plan までで停止

## リファレンス読み込み（必須）

処理を開始する前に、必ず以下のファイルをReadツールで読み込んでください:
- `reference/connector-catalog.md` — 対応コネクタの確認
- `reference/type-mapping.md` — フィールドタイプ変換表
- `reference/terraform-patterns.md` — HCL生成ルール・テンプレート

さらに、ソース/デスティネーションに応じて個別リファレンスも読み込む:
- ソースが kintone の場合: `reference/sources/kintone.md`
- デスティネーションが BigQuery の場合: `reference/destinations/bigquery.md`
- デスティネーションが Snowflake の場合: `reference/destinations/snowflake.md`

ソースまたはデスティネーションが connector-catalog.md に記載されていない場合は、
ユーザーに未対応であることを伝えて停止してください。

## 前提条件チェック（Step 0）

以下のコマンドをBashツールで実行して環境を確認:

```bash
# 1. Terraform v1.5以上が必要
terraform version

# 2. jq インストール確認
which jq

# 3. 環境変数の確認（デスティネーションに応じて動的にチェック）
if [ -f .env.local ]; then
  source .env.local
  echo "=== Common ==="
  echo "TROCCO_API_KEY: ${TROCCO_API_KEY:+configured}"
  echo ""
  echo "=== Source (kintone) ==="
  echo "KINTONE_CONNECTION_ID: ${KINTONE_CONNECTION_ID:-NOT SET}  ← 設定済みなら既存接続を使用"
  echo "KINTONE_DOMAIN: ${KINTONE_DOMAIN:-NOT SET}"
  echo "KINTONE_APP_ID: ${KINTONE_APP_ID:-NOT SET}"
  echo "KINTONE_API_TOKEN: ${KINTONE_API_TOKEN:+configured}"
  if [ -n "$KINTONE_CONNECTION_ID" ]; then
    echo "  → モードA: 既存接続ID=${KINTONE_CONNECTION_ID} を使用"
  else
    echo "  → モードB: Terraformで新規作成（domain/token必須）"
  fi
  echo ""
  echo "=== Destination (BigQuery) ==="
  echo "BQ_CONNECTION_ID: ${BQ_CONNECTION_ID:-NOT SET}"
  echo "BQ_DATASET: ${BQ_DATASET:-NOT SET}"
  echo "BQ_TABLE: ${BQ_TABLE:-NOT SET}"
  echo "BQ_LOCATION: ${BQ_LOCATION:-NOT SET}"
  echo ""
  echo "=== Destination (Snowflake) ==="
  echo "SNOWFLAKE_CONNECTION_ID: ${SNOWFLAKE_CONNECTION_ID:-NOT SET}  ← 設定済みなら既存接続を使用"
  echo "SNOWFLAKE_HOST: ${SNOWFLAKE_HOST:-NOT SET}"
  echo "SNOWFLAKE_USER: ${SNOWFLAKE_USER:-NOT SET}"
  echo "SNOWFLAKE_PASSWORD: ${SNOWFLAKE_PASSWORD:+configured}"
  echo "SNOWFLAKE_WAREHOUSE: ${SNOWFLAKE_WAREHOUSE:-NOT SET}"
  echo "SNOWFLAKE_DATABASE: ${SNOWFLAKE_DATABASE:-NOT SET}"
  if [ -n "$SNOWFLAKE_CONNECTION_ID" ]; then
    echo "  → モードA: 既存接続ID=${SNOWFLAKE_CONNECTION_ID} を使用"
  else
    echo "  → モードB: Terraformで新規作成（host/user/password必須）"
  fi
else
  echo ".env.local not found"
fi
```

不足している環境変数がある場合:
→ `.env.example` を参照するよう案内し、`.env.local` の設定を求めて停止

TROCCO_API_KEY は必須。ソース/デスティネーション固有の変数はパース結果に応じて確認:

**kintoneソース（2モード）:**
- **モードA（推奨）:** `KINTONE_CONNECTION_ID` が設定済み → 既存接続をIDで参照。`KINTONE_DOMAIN`/`KINTONE_API_TOKEN`は不要。`KINTONE_APP_ID`は必須。
- **モードB:** `KINTONE_CONNECTION_ID` が空 → `KINTONE_DOMAIN`, `KINTONE_API_TOKEN` が必須。Terraformで接続を新規作成。

**BigQueryデスティネーション:**
- `BQ_CONNECTION_ID`, `BQ_DATASET` が必須。BQ接続はTROCCO UIで事前作成が必要。

**Snowflakeデスティネーション（2モード）:**
- **モードA:** `SNOWFLAKE_CONNECTION_ID` が設定済み → 既存接続をIDで参照。
- **モードB:** `SNOWFLAKE_CONNECTION_ID` が空 → `SNOWFLAKE_HOST`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD` 等が必須。

## 処理フロー

### Step 1: ソース情報の取得

ソースタイプに応じた情報取得をBashツールで実行する。

#### kintone の場合

```bash
source .env.local
RESPONSE=$(curl -s "https://${KINTONE_DOMAIN}/k/v1/app/form/fields.json" \
  -G -d "app=${KINTONE_APP_ID}" \
  -H "X-Cybozu-API-Token: ${KINTONE_API_TOKEN}" \
  -w "\nHTTP_STATUS:%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '$d')
echo "$BODY" > /tmp/kintone-fields-response.json
echo "HTTP Status: $HTTP_CODE"
```

HTTPステータスコードを確認:
- 200: 正常 → 次のステップへ
- 401/403: 認証エラー → 「KINTONE_API_TOKENが無効、またはアプリへの閲覧権限がありません」と案内して停止
- 404: アプリ不存在 → 「KINTONE_APP_ID が正しいか確認してください」と案内して停止
- その他: エラー内容を表示して停止

#### MySQL の場合
→ 接続情報（MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, テーブル名）をユーザーに確認。TROCCOのconnection経由で管理するため、スキーマの事前取得は不要。

#### Salesforce の場合
→ SF_CONNECTION_ID（TROCCO上でOAuth接続済み）とオブジェクト名をユーザーに確認。

### Step 2: フィールド→カラム変換

**reference/type-mapping.md** の変換表に従い、取得したフィールド情報を解析する。

kintoneの場合:
```bash
jq -r '
  .properties | to_entries[]
  | select(IN(.value.type; "FILE","STATUS_ASSIGNEE","CATEGORY","REFERENCE_TABLE") | not)
  | [.key, .value.type, .value.label] | @tsv
' /tmp/kintone-fields-response.json | sort
```

> **注意:** jqフィルタはシングルクォートで囲む。不等号比較はINパターン（select + not）を使用。jqはファイル引数で呼ぶ。

type-mapping.md の変換ルールを適用し:
1. `input_option_columns` 配列を生成（kintoneフィールドコード + TROCCOカラムタイプ）
2. `filter_columns` 配列を生成（英語カラム名 + src + タイプ + format）

日本語フィールドコードの英語変換はあなた（Claude）の推論で実行してください。
例: `顧客名` → `customer_name`, `売上金額` → `sales_amount`

### Step 3: TROCCO接続情報の確認

ソース/デスティネーションの接続IDを決定する。
**接続IDが .env.local に設定済みの場合はAPI呼び出しをスキップし、そのIDを使用する。**

#### 接続ID確認用の共通関数

```bash
source .env.local

# 接続一覧を取得する関数（Not Authorized対応付き）
check_trocco_connection() {
  local conn_type="$1"
  local env_var_name="$2"
  local env_var_value="$3"

  echo "=== ${conn_type} connections ==="
  if [ -n "$env_var_value" ]; then
    echo "${env_var_name}=${env_var_value} (設定済み → このIDを使用)"
    return 0
  fi

  # 接続IDが未設定の場合のみAPIを呼び出す
  RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    "https://trocco.io/api/connections/${conn_type}" \
    -H "Authorization: Token ${TROCCO_API_KEY}")
  HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
  BODY=$(echo "$RESULT" | sed '$d')

  if [ "$HTTP_CODE" = "200" ]; then
    echo "$BODY" | jq '.items[] | {id, name}' 2>/dev/null || echo "既存接続なし"
  elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "API HTTP ${HTTP_CODE}: 接続一覧APIへのアクセス権限がありません"
    echo "→ TROCCO管理画面 > 接続情報 でIDを確認し .env.local に設定してください"
  else
    echo "API HTTP ${HTTP_CODE}: ${BODY}"
  fi
  echo "${env_var_name}: ${env_var_value:-NOT SET}"
}

check_trocco_connection "kintone" "KINTONE_CONNECTION_ID" "${KINTONE_CONNECTION_ID:-}"
echo ""
check_trocco_connection "bigquery" "BQ_CONNECTION_ID" "${BQ_CONNECTION_ID:-}"
```

> Snowflakeデスティネーションの場合は `check_trocco_connection "snowflake" "SNOWFLAKE_CONNECTION_ID" "${SNOWFLAKE_CONNECTION_ID:-}"` も追加。

#### kintone接続の判定ロジック

1. `KINTONE_CONNECTION_ID` が .env.local に設定済み → そのIDを使用（モードA）。API呼び出しスキップ。
2. `KINTONE_CONNECTION_ID` が空 → API一覧を試行:
   - API成功 + 既存接続あり → ユーザーにID設定を案内
   - API失敗（401/403） → TROCCO管理画面での手動確認を案内
   - 接続なし → Terraformで新規作成（モードB）。`KINTONE_DOMAIN`と`KINTONE_API_TOKEN`が必須。

#### BigQuery デスティネーションの判定ロジック

BigQuery接続はTROCCO UIでOAuth/サービスアカウントで作成済みのものを使用する:

- `BQ_CONNECTION_ID` が設定済み → そのIDを使用。API呼び出しスキップ。
- `BQ_CONNECTION_ID` が未設定 → API一覧を試行:
  - API成功 + 接続あり → 「.env.localの`BQ_CONNECTION_ID`にIDを設定してください」と案内
  - API失敗（401/403） → 「TROCCO管理画面 > 接続情報 でBigQuery接続IDを確認してください」と案内
  - 接続なし → 「TROCCO管理画面 > 接続情報 > 新規作成 > BigQuery でOAuth接続を作成してください」と案内して停止

#### Snowflake デスティネーションの判定ロジック

- `SNOWFLAKE_CONNECTION_ID` が設定済み → そのIDを使用（モードA）。API呼び出しスキップ。
- `SNOWFLAKE_CONNECTION_ID` が空 → API一覧を試行:
  - API成功 + 接続あり → ユーザーにID設定を案内
  - API失敗（401/403） → TROCCO管理画面での手動確認を案内
  - 接続なし → Terraformで新規作成（モードB）

### Step 4: Terraform HCL 生成

**reference/terraform-patterns.md** のルールに従い、Writeツールで以下を生成:

ディレクトリ: `pipelines/{source}-to-{dest}-{YYYYMMDD-HHMMSS}/`

1. `main.tf` — Provider設定 + Connection + Job Definition
2. `variables.tf` — 全変数定義（sensitive変数は `sensitive = true`）
3. `outputs.tf` — job_definition_id, connection_id, pipeline_summary
4. `terraform.tfvars` — 変数値（機密情報はtfvarsに書かない。TF_VAR_xxx環境変数で注入）

**HCL生成の重要ルール:**
- `required_version = ">= 1.5.0"` を必ず含める
- Provider: `trocco-io/trocco` version `~> 0.24`
- APIキー/パスワードをHCLにハードコードしない
- terraform.tfvars が `.gitignore` に含まれることを確認
- **`labels` は使用しない**（TROCCOで事前登録済みのラベル名のみ受け付けるため、自動生成では省略）

**デスティネーション別のHCL生成:**

- **BigQuery:** `output_option_type = "bigquery"` + `bigquery_output_option` ブロック。
  - BigQuery接続はTROCCO UIで作成済みのため、`bigquery_connection_id` で参照（Terraform connection resourceは不要）。
  - `location` はデフォルト `"US"` なので日本環境では `"asia-northeast1"` を明示指定。
  - `auto_create_dataset = true` でデータセット自動作成を有効化。
  - テンプレートは `reference/terraform-patterns.md` の「kintone → BigQuery」セクションを参照。

- **Snowflake:** `output_option_type = "snowflake"` + `snowflake_output_option` ブロック。
  - Snowflake接続はTerraformで新規作成（`trocco_connection.snowflake_dest`）。
  - テンプレートは `reference/terraform-patterns.md` の「kintone → Snowflake」セクションを参照。
  - plan失敗時は `reference/destinations/snowflake.md` のREST APIフォールバック手順を実行。

### Step 5: Terraform Plan（安全確認）

```bash
cd pipelines/{pipeline-name}
source ../../.env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# kintone接続: モードに応じてTF_VARを設定
if [ -n "$KINTONE_CONNECTION_ID" ]; then
  # モードA: 既存接続IDを参照
  export TF_VAR_kintone_connection_id="$KINTONE_CONNECTION_ID"
else
  # モードB: Terraformで新規作成
  export TF_VAR_kintone_api_token="$KINTONE_API_TOKEN"
fi

# Snowflakeデスティネーションの場合:
# if [ -n "$SNOWFLAKE_CONNECTION_ID" ]; then
#   export TF_VAR_snowflake_connection_id="$SNOWFLAKE_CONNECTION_ID"
# else
#   export TF_VAR_snowflake_password="$SNOWFLAKE_PASSWORD"
# fi

terraform init
terraform plan -out=tfplan 2>&1 | tee /tmp/terraform-plan-output.txt
```

**必ず plan の結果をユーザーに以下の形式で提示:**
- 作成されるリソース数（例: "3 to add, 0 to change, 0 to destroy"）
- 各リソースの概要（Connection名/タイプ、Job Definition名、転送カラム数）

**plan にエラーがある場合:** エラー内容を分析し、HCLを修正して再実行（最大3回まで）

**`--dry-run` が指定されている場合はここで停止。**

### Step 6: Terraform Apply（ユーザー承認後のみ）

**重要: ユーザーが明示的に「apply」「実行」「OK」等と承認した場合のみ実行すること。**

```bash
cd pipelines/{pipeline-name}
source ../../.env.local
export TF_VAR_trocco_api_key="$TROCCO_API_KEY"

# kintone接続: モードに応じてTF_VARを設定
if [ -n "$KINTONE_CONNECTION_ID" ]; then
  export TF_VAR_kintone_connection_id="$KINTONE_CONNECTION_ID"
else
  export TF_VAR_kintone_api_token="$KINTONE_API_TOKEN"
fi

# Snowflakeデスティネーションの場合:
# if [ -n "$SNOWFLAKE_CONNECTION_ID" ]; then
#   export TF_VAR_snowflake_connection_id="$SNOWFLAKE_CONNECTION_ID"
# else
#   export TF_VAR_snowflake_password="$SNOWFLAKE_PASSWORD"
# fi

terraform apply tfplan 2>&1 | tee /tmp/terraform-apply-output.txt
```

apply結果を確認し、作成されたリソースIDを記録。

### Step 7: テスト実行

```bash
source .env.local
JOB_DEF_ID=$(terraform -chdir=pipelines/{pipeline-name} output -raw job_definition_id)

# ジョブ実行（POST /api/jobs?job_definition_id={id}）
RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  "https://trocco.io/api/jobs?job_definition_id=${JOB_DEF_ID}" \
  -H "Authorization: Token ${TROCCO_API_KEY}")
HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESULT" | sed '$d')
echo "HTTP Status: $HTTP_CODE"
echo "$BODY" > /tmp/trocco-job-result.json
jq '.' /tmp/trocco-job-result.json
JOB_ID=$(jq -r '.id' /tmp/trocco-job-result.json)
```

ジョブ投入に成功したら、`GET /api/jobs/{id}` でステータスをポーリングする。
APIリファレンス: https://documents.trocco.io/apidocs/get-job

```bash
source .env.local

# 15秒待機してジョブ状態を確認（GET /api/jobs/{id}）
sleep 15
RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "https://trocco.io/api/jobs/${JOB_ID}" \
  -H "Authorization: Token ${TROCCO_API_KEY}")
HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESULT" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "$BODY" > /tmp/trocco-job-status.json
  jq '{id, status, started_at, finished_at}' /tmp/trocco-job-status.json
else
  echo "HTTP ${HTTP_CODE}: ジョブ実行結果APIへのアクセス権限がありません"
  echo "→ TROCCO管理画面 > ジョブ でジョブの実行状況を確認してください"
  echo "→ APIキーに「転送ジョブの閲覧」権限を追加するとAPI経由で確認できます"
fi
```

**ポーリング仕様:**
- ジョブの status が `queued`, `setting_up`, `executing` の場合は15秒間隔で最大4回（計60秒）ポーリング
- `succeeded` → 成功。Step 8 の結果レポートへ
- `error` → 失敗。TROCCO管理画面でジョブログを確認するよう案内
- HTTP 401/403 → APIキーに「転送ジョブの閲覧」権限がない。TROCCO管理画面で確認するよう案内し、ジョブ投入自体は成功している旨を伝えて Step 8 へ進む

**status値一覧:** `queued`, `setting_up`, `executing`, `interrupting`, `succeeded`, `error`, `canceled`, `skipped`

### Step 8: 結果レポート

以下の情報をまとめてユーザーに報告:

```
## パイプライン構築結果

- **パイプライン名:** {job_name}
- **ソース:** {source_type} ({source_detail})
- **デスティネーション:** {dest_type} ({dest_detail})
- **転送カラム数:** {column_count}
- **テスト実行:** {成功/失敗}
- **転送レコード数:** {record_count}

### 作成されたリソース
- Connection (Source): ID={id}
- Connection (Dest): ID={id}
- Job Definition: ID={id}

### 次のステップ
- [ ] デスティネーションでデータを確認
- [ ] スケジュール設定（必要な場合）
- [ ] TROCCOの管理画面で詳細を確認
```

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
| Snowflake output未対応 | plan時エラー | TROCCO REST API直接呼び出しにフォールバック（connector-catalog.md参照） |

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
