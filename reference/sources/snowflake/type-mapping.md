# Snowflake カラムタイプ → TROCCO カラムタイプ変換表

## 基本ルール

- 不明なカラムタイプは `string` にフォールバックし、警告を出力する
- NUMBER(p,0) は `long`、NUMBER(p,s) (s>0) は `double` として扱う
- VARIANT, OBJECT, ARRAY は `json` として取得
- TIMESTAMP 系はタイムゾーンの有無で format が異なる

## 変換マッピング

| Snowflake type | TROCCO column type | format | 備考 |
|----------------|-------------------|--------|------|
| VARCHAR, CHAR, TEXT, STRING | string | | |
| NUMBER(p,0), INT, INTEGER, BIGINT, SMALLINT, TINYINT, BYTEINT | long | | scale=0 の NUMBER |
| NUMBER(p,s) where s>0 | double | | scale>0 の NUMBER |
| FLOAT, FLOAT4, FLOAT8, DOUBLE, DOUBLE PRECISION, REAL | double | | |
| BOOLEAN | boolean | | |
| DATE | string | `%Y-%m-%d` | |
| TIME | string | `%H:%M:%S` | |
| TIMESTAMP, TIMESTAMP_NTZ | timestamp | `%Y-%m-%d %H:%M:%S` | タイムゾーンなし |
| TIMESTAMP_LTZ, TIMESTAMP_TZ | timestamp | `%Y-%m-%d %H:%M:%S %z` | タイムゾーン付き |
| VARIANT, OBJECT, ARRAY | json | | |
| BINARY, VARBINARY | string | | |
| GEOGRAPHY, GEOMETRY | string | | |

## filter_columns のカラム名変換ルール

Snowflake のカラム名はそのまま使用する（snake_case が一般的）。
大文字のカラム名は小文字に変換する。

### 変換ルール

1. Snowflake カラム名をそのまま小文字に変換（例: `ACCOUNT_ID` → `account_id`）
2. すでに小文字の場合はそのまま使用（例: `created_at` → `created_at`）
3. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）

## NUMBER 型の判定

Snowflake の `INFORMATION_SCHEMA.COLUMNS` から取得した場合:
- `NUMERIC_SCALE = 0` → `long`
- `NUMERIC_SCALE > 0` → `double`
- `NUMERIC_SCALE` が NULL（非数値型） → 他の型ルールに従う
