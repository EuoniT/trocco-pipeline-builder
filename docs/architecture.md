# Architecture

Technical design overview of TROCCO Pipeline Builder.

## Feasibility Assessment

### Summary: Feasible (Zero Programming)

| Item | Status | Note |
|------|--------|------|
| Claude Code Skill → Bash/Read/Write tools | **OK** | All tools available from Skill prompts |
| Terraform Provider kintone input | **OK** | `input_option_type = "kintone"` officially supported |
| Terraform Provider Snowflake output | **Caution** | Schema exists but no official example. REST API fallback available |
| kintone API → HCL conversion | **OK** | Get Form Fields API provides field definitions; Claude Code handles mapping |
| No programming required | **OK** | Markdown prompts + HCL declarations only |

### Definition of "No Programming"

Users write zero lines of Python, JavaScript, Shell scripts, or any procedural code. The system consists entirely of:
- **Markdown prompts** (`.claude/commands/setup-pipeline.md`) — declarative instructions
- **Terraform HCL** — declarative infrastructure configuration
- **Reference documents** (`reference/*.md`) — knowledge base for Claude Code

Claude Code autonomously executes `curl`, `jq`, and `terraform` commands based on prompt instructions.

## Processing Flow

```
User input: "/setup-pipeline kintone to Snowflake"
    │
    ▼
┌─────────────────────────────────────────┐
│ Step 0: Environment Check               │
│ - terraform version                     │
│ - TROCCO_API_KEY verification           │
│ - Source-specific env vars              │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 1: Source Schema Retrieval         │
│ curl → kintone Get Form Fields API     │
│ → /tmp/kintone-fields-response.json    │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 2: Field → Column Mapping          │
│ jq for field parsing                    │
│ kintone type → TROCCO column type      │
│ → input_option_columns array           │
│ → filter_columns array                 │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 3: TROCCO Connection Check         │
│ curl → TROCCO API (connections)        │
│ Existing → use ID                      │
│ None → create via Terraform            │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 4: Terraform HCL Generation        │
│ Write tool → main.tf                   │
│ Write tool → variables.tf              │
│ Write tool → outputs.tf                │
│ Write tool → terraform.tfvars          │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 5: terraform plan                  │
│ → Present results to user              │
│ → Fix HCL on error → re-plan          │
│ → Stop here if --dry-run               │
└─────────────┬───────────────────────────┘
              │ User approval
              ▼
┌─────────────────────────────────────────┐
│ Step 6: terraform apply                 │
│ → Capture resource IDs                 │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 7: Test Execution                  │
│ curl → TROCCO API (POST job)           │
│ → Poll for completion                  │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 8: Result Report                   │
│ Pipeline info, transfer results,       │
│ next steps                             │
└─────────────────────────────────────────┘
```

## Key Technical Decisions

### Why Terraform Provider (not REST API)?

| Aspect | Terraform | REST API |
|--------|-----------|----------|
| Declarative management | HCL files remain, reproducible | No state management |
| Change detection | `terraform plan` shows diffs | Manual tracking |
| Rollback | `terraform destroy` for cleanup | Manual DELETE calls |
| Auditability | HCL + state files serve as audit trail | Nothing persistent |

**Decision:** Terraform first, REST API as fallback for unsupported options.

### Why `.claude/commands/` (not `.claude/skills/`)?

- `commands/` is the established pattern for slash commands (`/setup-pipeline`)
- Reference files (`reference/`) are accessible via `Read` tool from any directory
- Migration to `skills/` is a simple directory rename if needed

### Snowflake Output Fallback Strategy

The `snowflake_output_option` exists in Terraform Provider schema but lacks official examples. If `terraform plan` fails:

1. Analyze the error message
2. Fall back to TROCCO REST API (`POST /api/job_definitions`) for Snowflake output
3. See `reference/connector-catalog.md` for API details

## Security Model

```
┌─────────────────────────────────────────────────┐
│ Layer 1: .env.local (local file)                │
│ - All credentials centralized here              │
│ - .gitignore protected                          │
│ - File permission: 600                          │
└──────────────────────┬──────────────────────────┘
                       │ source .env.local
                       ▼
┌─────────────────────────────────────────────────┐
│ Layer 2: Environment Variables                  │
│ - Valid only within Bash session                │
│ - Destroyed on process exit                     │
│ - Minimal writes to terraform.tfvars            │
└──────────────────────┬──────────────────────────┘
                       │ TF_VAR_xxx
                       ▼
┌─────────────────────────────────────────────────┐
│ Layer 3: Terraform Variables                    │
│ - sensitive = true marking                      │
│ - Plan output shows "(sensitive value)"         │
│ - State file stores values → .gitignore state   │
└─────────────────────────────────────────────────┘
```

### Safety Rules

1. `terraform apply` requires explicit user approval
2. Credentials loaded from `.env.local`, never hardcoded in HCL
3. `terraform.tfvars` and `*.tfstate` are gitignored
4. kintone record data is never fetched (field definitions only)
5. `--dry-run` flag stops at `terraform plan`

## Extensibility

Adding a new connector requires only 1 file:

```
reference/sources/{connector}.md    # or reference/destinations/{connector}.md
```

Update `reference/connector-catalog.md` with the new entry. No changes to `setup-pipeline.md` needed — Claude Code dynamically reads `reference/` at runtime.

## Technical Risks

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| R1 | Snowflake output unsupported in Terraform | High | REST API fallback (see connector-catalog.md) |
| R2 | kintone field type conversion gaps | Medium | Unknown types → `string` fallback + warning |
| R3 | Claude Code generates invalid HCL | Medium | `terraform plan` → self-correction loop (max 3 retries) |
| R4 | TROCCO API rate limiting | Low | Retry with exponential backoff |
| R5 | Terraform state conflicts | Medium | Independent directory per pipeline |

## References

- [TROCCO Terraform Provider](https://registry.terraform.io/providers/trocco-io/trocco/latest) (v0.24.0, 2026-02-05)
- [TROCCO API Documentation](https://documents.trocco.io/apidocs)
- [kintone Get Form Fields API](https://kintone.dev/en/docs/kintone/rest-api/apps/get-form-fields/)
- [kintone Developer License](https://kintone.dev/en/developer-license-registration-form/)
- [Snowflake Free Trial](https://signup.snowflake.com/)
