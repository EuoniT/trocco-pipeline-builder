---
name: test-and-report
description: TROCCOジョブのテスト実行・ステータスポーリング・結果レポートを行う
---

# テスト実行・結果レポート共通手順

オーケストレーター (`setup-pipeline.md`) から呼び出される共通手順。
terraform apply 完了後にジョブをテスト実行し、結果を報告する。

## 1. job_definition_id の取得

```bash
set -a && source .env.local && set +a
JOB_DEF_ID=$(terraform -chdir=pipelines/{pipeline-name} output -raw job_definition_id)
echo "Job Definition ID: $JOB_DEF_ID"
```

## 2. ジョブ実行

```bash
set -a && source .env.local && set +a
JOB_DEF_ID=$(terraform -chdir=pipelines/{pipeline-name} output -raw job_definition_id)

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

- HTTP 200/201: ジョブ投入成功 → ポーリングへ
- HTTP 401: `TROCCO_API_KEY` を確認するよう案内して停止
- HTTP 403: `API アクセスには Advanced 以上のプランが必要です` と案内

## 3. ジョブステータスのポーリング

ジョブ投入に成功したら、`GET /api/jobs/{id}` でステータスをポーリングする。
APIリファレンス: https://documents.trocco.io/apidocs/get-job

```bash
set -a && source .env.local && set +a

# 15秒待機してジョブ状態を確認
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

### ポーリング仕様

- ジョブの status が `queued`, `setting_up`, `executing` の場合は15秒間隔で最大4回（計60秒）ポーリング
- `succeeded` → 成功。結果レポートへ
- `error` → 失敗。TROCCO管理画面でジョブログを確認するよう案内
- HTTP 401/403 → APIキーに「転送ジョブの閲覧」権限がない。TROCCO管理画面で確認するよう案内し、ジョブ投入自体は成功している旨を伝えて結果レポートへ進む

### status値一覧

`queued`, `setting_up`, `executing`, `interrupting`, `succeeded`, `error`, `canceled`, `skipped`

## 4. 結果レポート

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

ソース/デスティネーションの詳細情報は、各Skillから取得した情報をもとに埋める。
