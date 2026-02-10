# Contributing to NL-to-Pipeline

Thank you for your interest in contributing!

## Adding a New Connector

The easiest way to contribute is adding support for a new data source or destination.

### Steps

1. Create a reference file:
   - Source: `reference/sources/{connector}.md`
   - Destination: `reference/destinations/{connector}.md`

2. Include in your reference file:
   - Required environment variables
   - Schema retrieval method (API call or manual)
   - Terraform `input_option_type` / `output_option_type`
   - Any connector-specific parameters

3. Add entry to `reference/connector-catalog.md`

4. (Optional) Add an example to `examples/{source}-to-{dest}/`

5. Test with `--dry-run`:
   ```
   /setup-pipeline {source} to {dest} --dry-run
   ```

**No changes to `setup-pipeline.md` are needed.** Claude Code dynamically reads `reference/` files at runtime.

## Development Setup

1. Fork and clone this repository
2. `cp .env.example .env.local`
3. Set up a TROCCO account (Advanced plan required for API access)
4. Test: `/setup-pipeline kintone to BigQuery --dry-run`

## Pull Request Guidelines

- One connector per PR
- Include `--dry-run` test output in PR description
- Update `reference/connector-catalog.md`
- Update `CHANGELOG.md`

## Reporting Issues

When reporting issues, please include:
- Claude Code version
- Terraform version (`terraform version`)
- `terraform plan` output (redact all credentials)
- Error messages

## Code of Conduct

Be respectful and constructive. We're all here to make data pipelines easier.
