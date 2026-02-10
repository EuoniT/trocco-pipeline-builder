# kintone → TROCCO カラムタイプ変換表

## 基本ルール

- 不明なフィールドタイプは `string` にフォールバックし、警告を出力する
- FILE タイプはスキップ（バイナリ転送不可）
- SUBTABLE は `expand_subtable = true` で展開する場合のみ対応
- STATUS_ASSIGNEE, CATEGORY, REFERENCE_TABLE はスキップ

## 変換マッピング

| kintone type | TROCCO column type | format | 備考 |
|-------------|-------------------|--------|------|
| SINGLE_LINE_TEXT | string | | |
| MULTI_LINE_TEXT | string | | |
| RICH_TEXT | string | | HTML含む |
| NUMBER | long | | 小数点なし整数の場合 |
| NUMBER | double | | 小数点あり（displayScale > 0）の場合 |
| DATE | timestamp | `%Y-%m-%d` | |
| DATETIME | timestamp | `%Y-%m-%dT%H:%M:%S%z` | |
| TIME | string | | HH:MM形式 |
| CHECK_BOX | json | | 配列 |
| RADIO_BUTTON | string | | |
| DROP_DOWN | string | | |
| MULTI_SELECT | json | | 配列 |
| USER_SELECT | json | | オブジェクト配列 |
| ORGANIZATION_SELECT | json | | オブジェクト配列 |
| GROUP_SELECT | json | | オブジェクト配列 |
| RECORD_NUMBER | long | | |
| CREATED_TIME | timestamp | `%Y-%m-%dT%H:%M:%S%z` | |
| UPDATED_TIME | timestamp | `%Y-%m-%dT%H:%M:%S%z` | |
| CREATOR | string | | code値のみ |
| MODIFIER | string | | code値のみ |
| CALC | string | | 計算結果の型が不定のためstringで安全に取得 |
| LINK | string | | URL/電話/メール |
| FILE | (skip) | | バイナリ転送不可 |
| SUBTABLE | (expand) | | expand_subtable=trueで子フィールドを展開 |
| STATUS | string | | プロセス管理ステータス |
| STATUS_ASSIGNEE | (skip) | | |
| CATEGORY | (skip) | | |
| REFERENCE_TABLE | (skip) | | 関連テーブル参照（実データなし） |

## NUMBER型の判定ロジック

kintone Get Form Fields APIのレスポンスで `"type": "NUMBER"` の場合:
- フィールド定義に `"digit": true` がある、または `"displayScale"` が `"0"` → `long`
- `"displayScale"` が `"1"` 以上 → `double`
- 判定不能な場合 → `long`（安全側に倒す）

## filter_columns のカラム名変換ルール

kintoneのフィールドコード（日本語可）から、デスティネーション側のカラム名に変換する。
Claude Codeの推論で日本語→英語スネークケース変換を実行する。

### 固定マッピング（システムフィールド）

| kintone フィールド | 変換後カラム名 |
|-------------------|---------------|
| レコード番号 / RECORD_NUMBER | record_number |
| 作成日時 / CREATED_TIME | created_at |
| 更新日時 / UPDATED_TIME | updated_at |
| 作成者 / CREATOR | created_by |
| 更新者 / MODIFIER | updated_by |

### 推論変換例（ユーザー定義フィールド）

| kintone フィールドコード | 変換後カラム名 |
|------------------------|---------------|
| 顧客名 | customer_name |
| 売上金額 | sales_amount |
| メールアドレス | email |
| 電話番号 | phone_number |
| 会社名 | company_name |
| 担当者 | owner |
| ステータス | status |
| 契約開始日 | contract_start_date |

変換時は以下のルールを適用:
1. ASCII英数字のみのフィールドコードはそのまま小文字化（例: `Email` → `email`）
2. 日本語フィールドコードは意味を保持した英語スネークケースに変換
3. 特殊文字やスペースはアンダースコアに置換
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）
