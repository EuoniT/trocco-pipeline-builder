# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Initial release
- `/setup-pipeline` Claude Code Skill
- kintone source support (Get Form Fields API integration)
- Snowflake destination support (Terraform + REST API fallback)
- BigQuery destination support (recommended for Phase 1)
- Reference documents: connector-catalog, type-mapping, terraform-patterns
- Individual connector references: `reference/sources/kintone.md`, `reference/destinations/bigquery.md`, `reference/destinations/snowflake.md`
- Example HCL: kintone-to-snowflake, kintone-to-bigquery
- `--dry-run` mode (plan only)
- Automatic field type mapping (kintone → TROCCO column types)
- Japanese field name → English snake_case conversion
- Apache License 2.0
