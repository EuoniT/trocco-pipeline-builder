# TROCCO Pipeline Builder へのコントリビューション

コントリビューションに興味を持っていただきありがとうございます！

## 新しいコネクタの追加

最も手軽なコントリビューション方法は、新しいデータソースやデスティネーションのサポートを追加することです。

### 手順

1. SKILL ファイルを作成:
   - ソース: `.claude/skills/sources/{connector}/SKILL.md`（テンプレート: `_template.md`）
   - デスティネーション: `.claude/skills/destinations/{connector}/SKILL.md`（テンプレート: `_template.md`）

2. Reference ディレクトリを作成:
   - ソース: `reference/sources/{connector}/` に以下を配置:
     - `README.md` — 概要・接続方法・Terraform設定
     - `type-mapping.md` — 型変換ルール
     - `env-vars.json` — 環境変数定義
   - デスティネーション: `reference/destinations/{connector}/` に以下を配置:
     - `README.md` — 概要・接続方法・Terraform設定
     - `env-vars.json` — 環境変数定義

3. （任意）`examples/{source}-to-{dest}/` にサンプルHCLを追加

4. `--dry-run` でテスト:
   ```
   /setup-pipeline {source} to {dest} --dry-run
   ```

**既存ファイルの修正は不要です。** Claude Code が Glob で SKILL と Reference を動的に検出します。

## 開発環境のセットアップ

1. このリポジトリをフォーク＆クローン
2. `cp .env.example .env.local`
3. TROCCO アカウントを用意（API アクセスには Advanced プランが必要）
4. テスト: `/setup-pipeline kintone to BigQuery --dry-run`

## プルリクエストのガイドライン

- 1つの PR につき 1 コネクタ
- PR の説明に `--dry-run` のテスト出力を含める
- `reference/sources/{connector}/` または `reference/destinations/{connector}/` を作成する
- `CHANGELOG.md` を更新する

## Issue の報告

Issue を報告する際は、以下の情報を含めてください：

- Claude Code のバージョン
- Terraform のバージョン（`terraform version`）
- `terraform plan` の出力（認証情報はすべてマスクしてください）
- エラーメッセージ

## 行動規範

敬意を持ち、建設的なコミュニケーションを心がけてください。このプロジェクトはデータパイプラインの構築をより簡単にすることを目指しています。
