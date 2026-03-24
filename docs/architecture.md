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
- **Markdown prompts** (`.claude/commands/setup-pipeline.md` + `skills/*.md`) — declarative instructions
- **Terraform HCL** — declarative infrastructure configuration
- **Reference documents** (`reference/*.md`) — knowledge base for Claude Code

Claude Code autonomously executes `curl`, `jq`, and `terraform` commands based on prompt instructions.

## Multi-Skill Architecture

The system uses a modular orchestrator pattern where `setup-pipeline.md` acts as the entry point,
dynamically selecting and composing source/destination Skills based on user input.

**Scalability:** M sources x N destinations = **M+N Skill files** (not M*N).

```
User input: "/setup-pipeline kintone to BigQuery"
        │
        ▼
┌───────────────────────────────────┐
│  setup-pipeline.md                │  ← Orchestrator (~120 lines)
│  - Parse input (source/dest)      │
│  - Check connector-catalog.md     │
│  - Read & execute source Skill    │
│  - Read destination Skill         │
│  - Integrate HCL generation       │
│  - Read & execute procedures      │
└──────┬──────────┬─────────────────┘
       │          │
  Read │          │ Read
       ▼          ▼
┌────────────┐ ┌─────────────────┐
│source_     │ │destination_     │
│kintone.md  │ │bigquery.md      │
│- Schema    │ │- Connection     │
│  retrieval │ │  check          │
│- Type      │ │- HCL rules     │
│  mapping   │ │- Output options │
│- Connection│ │                 │
│  check     │ │                 │
└────────────┘ └─────────────────┘
       │          │
       └────┬─────┘
            │ Read (as needed)
            ▼
┌───────────────────────────────┐
│  .claude/skills/infrastructure/│  ← Common procedure Skills
│  - env-check/SKILL.md         │
│  - terraform-execute/SKILL.md │
│  - test-and-report/SKILL.md   │
└───────────────────────────────┘
```

### Skill Responsibilities

| Component | Responsibility |
|-----------|----------------|
| Orchestrator (`setup-pipeline.md`) | Input parsing, Skill selection, HCL integration, safety rules |
| Source Skills (`skills/sources/{connector}/SKILL.md`) | Schema retrieval, type mapping, source connection check, input_option HCL |
| Destination Skills (`skills/destinations/{connector}/SKILL.md`) | Destination connection check, output_option HCL, load modes |
| Common Procedure Skills (`skills/infrastructure/`) | Environment check, terraform plan/apply, test execution & reporting |

### Adding a New Connector

**New source:**
1. Copy `.claude/skills/sources/_template.md` to `.claude/skills/sources/{name}/SKILL.md`
2. Replace placeholders and add connector-specific logic
3. (Optional) Create `reference/sources/{name}.md` for detailed reference
4. Add entry to `reference/connector-catalog.md`
5. Add environment variable definitions to `.claude/skills/infrastructure/generate-env/env-vars.json` (`sources` section)
6. **No changes to orchestrator required** (dynamic Skill detection via Glob)

**New destination:**
1. Copy `.claude/skills/destinations/_template.md` to `.claude/skills/destinations/{name}/SKILL.md`
2. Replace placeholders and add connector-specific logic
3. (Optional) Create `reference/destinations/{name}.md` for detailed reference
4. Add entry to `reference/connector-catalog.md`
5. Add HCL template to `reference/terraform-patterns.md`
6. Add environment variable definitions to `.claude/skills/infrastructure/generate-env/env-vars.json` (`destinations` section)
7. **No changes to orchestrator required**

## Processing Flow

```
User input: "/setup-pipeline kintone to Snowflake"
    │
    ▼
┌─────────────────────────────────────────┐
│ Pre-Step: .env.local Template           │
│ - Check if .env.local exists            │
│ - If missing: generate template via     │
│   generate-env Skill, then stop         │
│ - If exists: proceed to Step 0          │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 0: Environment Check               │
│ Read: .claude/skills/infrastructure/     │
│       env-check/SKILL.md                │
│ - terraform version, jq check           │
│ - TROCCO_API_KEY verification           │
│ - Source/dest env vars (from Skills)    │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 1-3 (src): Source Skill Execution  │
│ Read: skills/sources/{src}/SKILL.md     │
│ - Schema/field retrieval                │
│ - Field → column type mapping           │
│ - Source connection check               │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 3 (dest): Destination Skill        │
│ Read: skills/destinations/{dest}/SKILL.md│
│ - Destination connection check          │
│ - Output option HCL info               │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 4: Terraform HCL Generation        │
│ Integrate source + dest HCL info        │
│ Write: main.tf, variables.tf,           │
│        outputs.tf, terraform.tfvars     │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 5-6: Terraform Plan/Apply          │
│ Read: .claude/skills/infrastructure/     │
│       terraform-execute/SKILL.md        │
│ → Plan → user approval → apply         │
│ → Stop here if --dry-run               │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Step 7-8: Test & Report                 │
│ Read: .claude/skills/infrastructure/     │
│       test-and-report/SKILL.md          │
│ → Execute job → poll → report          │
└─────────────────────────────────────────┘
```

## 環境変数テンプレート生成

`.claude/skills/infrastructure/generate-env/SKILL.md` が `.env.local` テンプレート生成を担当する。
同ディレクトリの `env-vars.json` を Read で読み取り、指定されたソース/デスティネーションに必要な変数のみを含むテンプレートを Write ツールで出力する（外部スクリプト不要）。

`env-vars.json` は全コネクタの環境変数定義を構造化データとして持つ。Skill のデータソースであると同時に、新規コネクタ追加時の変数登録先でもある。

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

Adding a new connector requires only 1 Skill file + optional reference. Use the provided templates:

```
.claude/skills/sources/_template.md                    # Source template (copy to start)
.claude/skills/sources/{connector}/SKILL.md            # Source Skill
.claude/skills/destinations/_template.md               # Destination template (copy to start)
.claude/skills/destinations/{connector}/SKILL.md       # Destination Skill
reference/sources/{connector}.md                       # (Optional) Detailed reference
reference/destinations/{connector}.md                  # (Optional) Detailed reference
```

Update `reference/connector-catalog.md` with the new entry. No changes to the orchestrator (`setup-pipeline.md`) needed — it dynamically detects Skills via Glob at runtime.

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
