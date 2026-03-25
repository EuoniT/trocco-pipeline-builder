# Salesforce フィールドタイプ → TROCCO カラムタイプ変換表

## 基本ルール

- 不明なフィールドタイプは `string` にフォールバックし、警告を出力する
- base64 タイプはスキップ（バイナリ転送不可）
- address, location は `json` として取得（複合フィールド）
- time タイプは `string` として取得（HH:mm:ss.SSS形式）

## 変換マッピング

| Salesforce type | TROCCO column type | format | 備考 |
|----------------|-------------------|--------|------|
| id | string | | Salesforce レコードID（18文字） |
| string | string | | |
| textarea | string | | |
| email | string | | |
| phone | string | | |
| url | string | | |
| picklist | string | | |
| multipicklist | string | | セミコロン区切り |
| reference | string | | 参照先ID |
| combobox | string | | |
| encryptedstring | string | | |
| int | long | | |
| double | double | | |
| currency | double | | |
| percent | double | | |
| boolean | boolean | | |
| date | timestamp | `%Y-%m-%d` | |
| datetime | timestamp | `%Y-%m-%dT%H:%M:%S.000Z` | Salesforce API は UTC（`Z`末尾）で返す |
| time | string | | HH:mm:ss.SSS形式 |
| base64 | (skip) | | バイナリ転送不可 |
| address | json | | 複合フィールド（street, city, state等） |
| location | json | | 複合フィールド（latitude, longitude） |

## textarea フィールドの制限事項

textarea フィールド（BillingStreet, ShippingStreet, Description 等）は改行文字（`\n`, `\r`）を含む場合があり、
TROCCO の内部 CSV パーサー（Embulk）がマルチラインフィールドを正しく処理できないため、**SOQL の SELECT 句から除外する必要がある**。

- `filter_gsub` による改行除去は、CSV パースが filter 適用前に失敗するため効果なし
- Salesforce Describe API でフィールドの `type` が `textarea` のものを特定し、SOQL / input_columns / filter_columns から除外すること

## filter_columns のカラム名変換ルール

Salesforce のAPIフィールド名（英語CamelCase）から、デスティネーション側のカラム名に変換する。
CamelCase → snake_case 変換を適用する。Salesforce APIフィールド名は英語のため日本語変換は不要。

### 固定マッピング（標準フィールド）

| Salesforce フィールド | 変換後カラム名 |
|---------------------|---------------|
| Id | id |
| Name | name |
| CreatedDate | created_date |
| LastModifiedDate | last_modified_date |
| CreatedById | created_by_id |
| LastModifiedById | last_modified_by_id |
| OwnerId | owner_id |
| IsDeleted | is_deleted |

### 変換ルール

1. CamelCase をアンダースコア区切りに変換（例: `CreatedDate` → `created_date`）
2. 連続する大文字は1語として扱う（例: `SLAExpirationDate` → `sla_expiration_date`）
3. `__c` サフィックス（カスタムフィールド）はそのまま保持（例: `Custom_Field__c` → `custom_field__c`）
4. 重複する場合はサフィックスに数字を付与（例: `name_1`, `name_2`）
