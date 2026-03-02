# TROCCO Terraform Provider & API 情報

## Terraform Provider 情報

- **Provider:** `trocco-io/trocco`
- **推奨バージョン:** `~> 0.24`
- **Terraform本体:** `>= 1.5.0`
- **リポジトリ:** https://github.com/trocco-io/terraform-provider-trocco
- **Terraform Registry:** https://registry.terraform.io/providers/trocco-io/trocco/latest
- **リージョン値:** `"japan"`, `"india"`, `"korea"`（v0.24で `"jp"` 等は廃止）
- **接続リソース:** `trocco_connection` の属性はフラット構造（ネストブロック不使用）

## TROCCO API 情報

- **ベースURL:** `https://trocco.io/api`
- **認証:** `Authorization: Token <TROCCO_API_KEY>`
- **レート制限:** 3,500 calls/10min（Advanced以上のプランで利用可能）
- **APIドキュメント:** https://documents.trocco.io/apidocs

### 主要エンドポイント

| メソッド | エンドポイント | 用途 |
|---------|-------------|------|
| GET | /api/connections/{connection_type} | 接続情報一覧取得 |
| GET | /api/connections/{connection_type}/{id} | 接続情報詳細取得 |
| GET | /api/job_definitions | ジョブ定義一覧取得 |
| POST | /api/job_definitions | ジョブ定義作成 |
| POST | /api/jobs?job_definition_id={id} | ジョブ実行 |
| GET | /api/jobs/{id} | ジョブ実行結果取得（※1） |

> **※1 ジョブ実行結果取得API (`GET /api/jobs/{id}`) について:**
> - APIキーに「転送ジョブの閲覧」権限が必要
> - `"Not Authorized"` が返る場合はTROCCO管理画面でAPIキーの権限設定を確認
> - status値: `queued`, `setting_up`, `executing`, `interrupting`, `succeeded`, `error`, `canceled`, `skipped`
> - APIリファレンス: https://documents.trocco.io/apidocs/get-job

> **接続情報一覧API仕様:**
> - `connection_type` はパスパラメータ（クエリパラメータではない）
> - クエリパラメータ: `limit`（最大200、デフォルト50）、`cursor`（ページネーション）
> - レスポンス: `items[]` 配列（各要素に `id`, `name`, `description` 等）
> ```bash
> curl -s "https://trocco.io/api/connections/kintone" \
>   -H "Authorization: Token ${TROCCO_API_KEY}" \
>   | jq '.items[] | {id, name}'
> ```
> 参照: https://documents.trocco.io/apidocs/get-connection-configurations
>
> **注意:** 接続情報一覧APIはAPIキーの権限スコープに「接続情報の閲覧」が
> 含まれている必要があります。`"Not Authorized"` エラーが返る場合は、
> TROCCO管理画面でAPIキーの権限設定を確認してください。
> 接続IDが既知の場合は、`.env.local` に直接設定することでこのAPIの
> 呼び出しをスキップできます。
