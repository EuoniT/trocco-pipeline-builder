# Amazon S3 / ファイルベースソース 型変換ルール

### 基本ルール

- ファイルフォーマットによって型推論方法が異なる
- パーサーが解釈できない型は `string` にフォールバック
- 判定不能な場合のデフォルトは `string`（最も安全）
- Claude Code がサンプルデータから型を推論し、ユーザーに確認を取る

### CSV 型推論ルール

CSV はすべてのフィールドが文字列として読み込まれるため、サンプルデータから型を推論する。
Google Spreadsheets と同じ推論ルールを適用:

| データパターン | TROCCO column type | format | 備考 |
|---------------|-------------------|--------|------|
| 整数のみ（1, 100, -5） | long | | 小数点なし |
| 小数を含む（1.5, 0.99） | double | | 小数点あり |
| `YYYY-MM-DD` 形式 | timestamp | `%Y-%m-%d` | 日付のみ |
| `YYYY-MM-DD HH:MM:SS` 形式 | timestamp | `%Y-%m-%d %H:%M:%S` | 日時 |
| `YYYY/MM/DD` 形式 | timestamp | `%Y/%m/%d` | 日付（スラッシュ区切り） |
| `YYYY/MM/DD HH:MM:SS` 形式 | timestamp | `%Y/%m/%d %H:%M:%S` | 日時（スラッシュ区切り） |
| ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`) | timestamp | `%Y-%m-%dT%H:%M:%S%z` | タイムゾーン付き |
| `TRUE` / `FALSE` | boolean | | ブーリアン |
| JSON配列・オブジェクト | json | | JSON文字列 |
| それ以外 | string | | デフォルト |

### JSONL 型推論ルール

JSONL はネイティブのJSON型情報を持つため、型マッピングが直接的:

| JSON 値の型 | TROCCO column type | format | 備考 |
|------------|-------------------|--------|------|
| string（日付パターンなし） | string | | |
| string（`YYYY-MM-DD` パターン） | timestamp | `%Y-%m-%d` | 日付文字列 |
| string（`YYYY-MM-DDTHH:MM:SS` パターン） | timestamp | `%Y-%m-%dT%H:%M:%S%z` | 日時文字列 |
| number（整数） | long | | 小数点なし |
| number（小数） | double | | 小数点あり |
| boolean | boolean | | |
| object | json | | ネストオブジェクト |
| array | json | | 配列 |
| null | string | | nullのみの場合はstringにフォールバック |

### Parquet 型推論ルール

Parquet はスキーマ情報を内包するため、Arrow型からの直接マッピング:

| Parquet / Arrow 型 | TROCCO column type | format | 備考 |
|-------------------|-------------------|--------|------|
| INT32, INT64 | long | | 整数 |
| FLOAT, DOUBLE | double | | 浮動小数点 |
| BYTE_ARRAY (UTF8) | string | | 文字列 |
| BOOLEAN | boolean | | |
| DATE | timestamp | `%Y-%m-%d` | 日付 |
| TIMESTAMP | timestamp | `%Y-%m-%d %H:%M:%S` | タイムスタンプ |
| DECIMAL | double | | 小数 |
| LIST, MAP, STRUCT | json | | 複合型 |

### LTSV 型推論ルール

LTSV はすべてのフィールドが文字列として読み込まれるため、CSV と同じ推論ルールを適用する。

### Excel 型推論ルール

Excel はセルの書式情報から型を推論:

| Excel セル型 | TROCCO column type | format | 備考 |
|-------------|-------------------|--------|------|
| 数値（整数） | long | | 小数桁なし |
| 数値（小数） | double | | 小数桁あり |
| 日付 | timestamp | `%Y-%m-%d %H:%M:%S` | Excelの日付シリアル |
| 文字列 | string | | |
| ブーリアン | boolean | | |
| その他 | string | | デフォルト |

### Excel formula_handling

Excel パーサーの `columns` には、各カラムに `formula_handling` フィールドが必須:

| 値 | 説明 | 推奨 |
|----|------|------|
| `cashed_value` | セルのキャッシュ値（表示値）を使用 | 推奨デフォルト |
| `evaluate` | 数式を評価して結果を取得 | 計算結果が必要な場合 |

> **⚠ Provider 命名注意:** `cashed_value` は Provider 側の命名（typo）。`cached_value` ではない。

```hcl
# Excel columns の例
columns = [
  { name = "id",     type = "long",   formula_handling = "cashed_value" },
  { name = "name",   type = "string", formula_handling = "cashed_value" },
  { name = "amount", type = "double", formula_handling = "evaluate" },
]
```

### filter_columns のカラム名変換ルール

ファイルのヘッダー/キー名から、デスティネーション側のカラム名に変換する。
Claude Code の推論で英語スネークケース変換を実行する。

変換時は以下のルールを適用:
1. ASCII英数字のみのヘッダーはそのまま小文字化（例: `Email` → `email`）
2. 日本語ヘッダーは意味を保持した英語スネークケースに変換（例: `顧客名` → `customer_name`）
3. スペースや特殊文字はアンダースコアに置換（例: `First Name` → `first_name`）
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）
5. JSONL のネストキーはドット区切りをアンダースコアに変換（例: `address.city` → `address_city`）
