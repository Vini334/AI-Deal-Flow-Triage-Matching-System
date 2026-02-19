# AI Deal Flow Triage & Matching System

A production-grade n8n automation workflow that processes inbound startup deal submissions through AI-powered analysis, deterministic validation, and rule-based thesis matching — with full observability, idempotency enforcement, and Slack notifications.

A personal project exploring how AI and deterministic automation can work together in venture capital workflows.

---

## Architecture Overview

```
Webhook POST ─► Normalize & Hash ─► Idempotency Check ─► Duplicate Detection
                                           │                      │
                                      (replay?)              (duplicate?)
                                           │                      │
                                     ┌─ Yes ─► 200 Already    ┌─ Yes ─► 200 Duplicate
                                     │         Processed       │
                                     └─ No ──────────────────► └─ No ──►
                                                                        │
                    Gemini 2.5 Flash ◄──────────────────────────────────┘
                         │
                    Parse & Validate JSON Schema
                         │
                    Score Consistency Guardrail
                         │
                    Force Fit Score Override (demo)
                         │
                    Log Score Events
                         │
                    Thesis Matching Engine
                         │
                    Save to Supabase ─► Log + Notify ─► Slack + Respond 201
```

---

## Flow Explanation (Step by Step)

| Step | Node | Description |
|------|------|-------------|
| 1 | **Webhook - Deal Intake** | Receives `POST /webhook/deal-flow-intake` with startup data |
| 2 | **Normalize & Validate** | Validates required fields, normalizes casing, generates SHA-256 `source_hash` from canonical payload |
| 3 | **Validation Error?** | Routes invalid payloads to a 400 error response |
| 4 | **Log Intake Event** | Writes `intake_received` event to `event_logs` |
| 5 | **Check Idempotent** | Queries Supabase for existing deal with same `source_hash` |
| 6 | **Evaluate Idempotent** | Determines if this is a replay of an already-processed submission |
| 7 | **Is Replay?** | Routes replays to a 200 "already processed" response (with event log) |
| 8 | **Check Duplicate** | Queries Supabase for existing deal with same `website` |
| 9 | **Evaluate Duplicate** | Determines if a deal already exists for this company's website |
| 10 | **Is Duplicate?** | Routes duplicates to update timestamp + log + 200 response |
| 11 | **Build Gemini Body** | Constructs the LLM prompt with scoring rubric and consistency rules |
| 12 | **Gemini - Generate Memo** | Calls Gemini 2.5 Flash with structured JSON output mode |
| 13 | **Parse & Validate Memo** | Strict JSON schema validation of LLM output (types, ranges, structure) |
| 14 | **Schema OK?** | Routes schema failures to a 422 error response |
| 15 | **Score Consistency Guardrail** | Clamps `fit_score` upward if reasoning contains high-confidence language but score is below threshold |
| 16 | **Force Fit Score Override** | Demo-only: allows `force_fit_score` field to override the AI score for testing |
| 17 | **Log Score Events** | Logs `score_consistency_fix` and `force_fit_score_used` events to Supabase |
| 18 | **Thesis Matching** | Rule-based classification: maps sector + stage + score to `Qualified` / `Review` / `Pass` |
| 19 | **Save Deal to Supabase** | Persists complete deal record to `deals` table |
| 20 | **Build Log & Response** | Constructs event log body, API response body, and Slack message |
| 21 | **Log Deal Created** | Writes `deal_created` event with processing metrics |
| 22 | **Insert Notification Queue** | Persists notification to `notifications_queue` table |
| 23 | **Slack Notification** | Sends formatted deal summary to Slack channel |
| 24 | **Respond - Success** | Returns 201 with deal ID, score, status, and processing time |

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Workflow Engine | [n8n](https://n8n.io) (cloud or self-hosted) |
| AI Model | Google Gemini 2.5 Flash (`generativelanguage.googleapis.com`) |
| Database | [Supabase](https://supabase.com) (PostgreSQL) |
| Notifications | Slack Incoming Webhooks |
| Hashing | SHA-256 (Node.js `crypto` module) |
| Schema Validation | Custom deterministic JS validators |

---

## Key Engineering Decisions

### Deterministic Hashing
Every inbound payload is normalized (lowercased, whitespace-collapsed) and hashed with SHA-256 to produce a `source_hash`. This canonical fingerprint enables replay detection regardless of superficial formatting differences.

### Idempotency
Before any processing, the workflow queries Supabase for an existing deal with the same `source_hash`. Replayed requests receive a 200 response without re-processing, preventing duplicate AI calls and database writes.

### Duplicate Protection
A second check queries by `website` domain. If a deal already exists for the same company website (even with a different payload), it is flagged as a duplicate, the existing record's timestamp is updated, and the event is logged.

### LLM Schema Validation
The Gemini response is validated against a strict schema: `fit_score` must be an integer 0-100, `executive_summary` must be a string, `strengths`/`risks`/`diligence_questions` must be arrays of strings, and `fit_reasoning` must be a string. Schema failures return a 422 error instead of persisting invalid data.

### Score Consistency Guardrail
A post-LLM guardrail detects contradictions between reasoning language and numeric scores. If the `fit_reasoning` contains high-confidence phrases (e.g., "very strong", "compelling", "exceptional") but the `fit_score` is below 70, the score is clamped upward to 70 and the correction is logged.

### Rule-Based Thesis Engine
Classification is deterministic, not AI-driven:
- **Qualified**: Sector matches thesis targets (`B2B SaaS`, `Fintech Infra`, `Climate Tech`) AND stage matches (`Pre-seed`, `Seed`, `Series A`) AND `fit_score > 65`
- **Review**: `fit_score` between 50-65
- **Pass**: Everything else

### Full Observability
Every workflow branch writes structured events to `event_logs`: `intake_received`, `idempotent_replay`, `duplicate_detected`, `score_consistency_fix`, `force_fit_score_used`, `deal_created`. Each event includes relevant context for debugging and audit.

---

## Setup Instructions

### Prerequisites
- n8n instance (cloud or self-hosted)
- Supabase project
- Google AI Studio account (Gemini API key)
- Slack workspace with Incoming Webhook configured

### 1. Create Supabase Tables

Run the SQL in [`schema.sql`](./schema.sql) in your Supabase SQL Editor. This creates the `deals`, `event_logs`, and `notifications_queue` tables with appropriate indexes.

### 2. Configure Environment Variables

Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

| Variable | Where to Get It |
|----------|----------------|
| `GEMINI_API_KEY` | [Google AI Studio](https://aistudio.google.com/apikey) |
| `SUPABASE_URL` | Supabase Dashboard > Settings > API > Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard > Settings > API > Service Role Key |
| `SLACK_WEBHOOK_URL` | Slack > Apps > Incoming Webhooks > Add New |

**For n8n Cloud:** Add these variables in Settings > Environment Variables.

**For self-hosted n8n:** Set them in your `.env` file or Docker environment.

### 3. Import Workflow

1. Open your n8n instance
2. Go to **Workflows** > **Add Workflow** > **Import from File**
3. Select `workflow.json`
4. The workflow will be imported in **inactive** state

### 4. Activate & Test

Activate the workflow, then test with a curl request:

```bash
curl -X POST https://your-n8n-instance/webhook/deal-flow-intake \
  -H "Content-Type: application/json" \
  -d '{
    "company_name": "TestCo",
    "website": "https://testco.io",
    "sector": "B2B SaaS",
    "stage": "Seed",
    "geography": "US",
    "pitch": "TestCo is a B2B SaaS platform that automates compliance reporting for mid-market fintech companies. We have 50 paying customers and $400K ARR."
  }'
```

**Expected Response (201):**
```json
{
  "status": "success",
  "deal_id": "uuid-here",
  "company": "TestCo",
  "fit_score": 78,
  "deal_status": "Qualified",
  "processing_time_ms": 3200
}
```

### 5. Test Idempotency

Send the same payload again. Expected response:

```json
{
  "status": "already_processed",
  "message": "Request already processed",
  "deal_id": "uuid-here",
  "source_hash": "sha256-hash"
}
```

---

## Demo Override: `force_fit_score`

For testing and demonstration purposes, you can override the AI-generated score by including a `force_fit_score` field in the webhook payload:

```bash
curl -X POST https://your-n8n-instance/webhook/deal-flow-intake \
  -H "Content-Type: application/json" \
  -d '{
    "company_name": "DemoOverride Inc",
    "website": "https://demo-override.io",
    "sector": "Climate Tech",
    "stage": "Pre-seed",
    "geography": "EU",
    "pitch": "Demo company for testing score override behavior.",
    "force_fit_score": 85
  }'
```

This bypasses the Gemini score and guardrail, allowing you to test specific thesis matching paths. The override is logged as a `force_fit_score_used` event for auditability.

> **Note:** This feature is intended for demo/testing only. Remove or gate it behind an environment variable before deploying to production.

---

## Security

- No API keys, tokens, or secrets are stored in this repository
- All credentials are referenced via `$env` environment variables
- The `pinData` section contains sanitized example data only
- Instance metadata has been neutralized
- The `.gitignore` excludes `.env` files and the original unsanitized export

---

## Why This Matters for AI-First Operations

This system demonstrates five principles that define production-grade AI automation:

### 1. AI + Deterministic Logic Integration
The LLM (Gemini) handles the subjective task it's suited for — analyzing startup pitches and generating structured investment memos. Everything else is deterministic: hashing, validation, schema enforcement, thesis matching, and routing. AI is used where it adds value; rules govern where correctness is non-negotiable.

### 2. Production Readiness
Idempotency enforcement, duplicate detection, retry configuration, timeout handling, and structured error responses make this workflow safe for real traffic. Replayed or duplicate submissions are handled gracefully, not silently duplicated.

### 3. Observability
Every decision point writes a structured event to `event_logs` with contextual payloads. Score corrections, overrides, replays, and duplicates are all tracked. This creates a full audit trail for debugging, compliance, and performance analysis.

### 4. Guardrails
The score consistency guardrail catches a known LLM failure mode: generating enthusiastic reasoning paired with a contradictorily low score. Rather than trusting the model blindly, the system detects and corrects the inconsistency, then logs the intervention.

### 5. Responsible LLM Usage
- The LLM output is schema-validated before any persistence
- Schema failures are surfaced as errors, not silently accepted
- The system never persists invalid or unparseable AI output
- Score corrections are transparent and auditable
- The force-fit override is logged and clearly marked as a demo feature

---

## Repository Structure

```
.
├── workflow.json       # Sanitized n8n workflow (import this)
├── schema.sql          # Supabase table definitions
├── .env.example        # Environment variable template
├── .gitignore          # Excludes secrets and local files
└── README.md           # This file
```

---

## License

MIT
