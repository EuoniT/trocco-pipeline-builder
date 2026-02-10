# TROCCO Pipeline Builder へのコントリビューション

コントリビューションに興味を持っていただきありがとうございます！

## 新しいコネクタの追加

最も手軽なコントリビューション方法は、新しいデータソースやデスティネーションのサポートを追加することです。

### 手順

1. リファレンスファイルを作成:
   - ソース: `reference/sources/{connector}.md`
   - デスティネーション: `reference/destinations/{connector}.md`

2. リファレンスファイルに以下を記載:
   - 必要な環境変数
   - スキーマ取得方法（API コールまたは手動）
   - Terraform の `input_option_type` / `output_option_type`
   - コネクタ固有のパラメータ

3. `reference/connector-catalog.md` にエントリを追加

4. （任意）`examples/{source}-to-{dest}/` にサンプルを追加

5. `--dry-run` でテスト:
   ```
   /setup-pipeline {source} to {dest} --dry-run
   ```

**`setup-pipeline.md` の変更は不要です。** Claude Code が実行時に `reference/` ファイルを動的に読み取ります。

## 開発環境のセットアップ

1. このリポジトリをフォーク＆クローン
2. `cp .env.example .env.local`
3. TROCCO アカウントを用意（API アクセスには Advanced プランが必要）
4. テスト: `/setup-pipeline kintone to BigQuery --dry-run`

## プルリクエストのガイドライン

- 1つの PR につき 1 コネクタ
- PR の説明に `--dry-run` のテスト出力を含める
- `reference/connector-catalog.md` を更新する
- `CHANGELOG.md` を更新する

## Issue の報告

Issue を報告する際は、以下の情報を含めてください：

- Claude Code のバージョン
- Terraform のバージョン（`terraform version`）
- `terraform plan` の出力（認証情報はすべてマスクしてください）
- エラーメッセージ

## 行動規範

敬意を持ち、建設的なコミュニケーションを心がけてください。このプロジェクトはデータパイプラインの構築をより簡単にすることを目指しています。
