# Google Spreadsheets 型変換ルール

### 基本ルール

- Google Spreadsheets にはフォーマルな型定義がないため、**サンプルデータからの推論** で型を決定する
- 判定不能な場合のデフォルトは `string`（最も安全）
- Claude Code がヘッダー行とサンプルデータを見て型を推論し、ユーザーに確認を取る

### 推論ルール

| データパターン | TROCCO column type | format | 備考 |
|---------------|-------------------|--------|------|
| 整数のみ（1, 100, -5） | long | | 小数点なし |
| 小数を含む（1.5, 0.99） | double | | 小数点あり |
| `YYYY-MM-DD` 形式 | timestamp | `%Y-%m-%d` | 日付のみ |
| `YYYY-MM-DD HH:MM:SS` 形式 | timestamp | `%Y-%m-%d %H:%M:%S` | 日時 |
| `YYYY/MM/DD` 形式 | timestamp | `%Y/%m/%d` | 日付（スラッシュ区切り） |
| `YYYY/MM/DD HH:MM:SS` 形式 | timestamp | `%Y/%m/%d %H:%M:%S` | 日時（スラッシュ区切り） |
| `TRUE` / `FALSE` | boolean | | ブーリアン |
| JSON配列・オブジェクト | json | | JSON文字列 |
| それ以外 | string | | デフォルト |

### 型推論の流れ

1. ヘッダー行からカラム名を取得
2. カラム名とサンプルデータ（あれば）をユーザーに確認
3. Claude Code がカラム名・サンプルデータから型を推論
4. 推論結果をユーザーに提示し、修正があれば反映

### filter_columns のカラム名変換ルール

Google Spreadsheets のヘッダー名から、デスティネーション側のカラム名に変換する。
Claude Code の推論で英語スネークケース変換を実行する。

変換時は以下のルールを適用:
1. ASCII英数字のみのヘッダーはそのまま小文字化（例: `Email` → `email`）
2. 日本語ヘッダーは意味を保持した英語スネークケースに変換（例: `顧客名` → `customer_name`）
3. スペースや特殊文字はアンダースコアに置換（例: `First Name` → `first_name`）
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）
