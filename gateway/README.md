# ScreenTidy AI Gateway

Stateless HTTPS-facing AI understanding proxy for ScreenTidy.

The iOS app never holds provider API keys. This service accepts ephemeral screenshot understanding requests, calls the OpenAI **Responses API** with multimodal input + strict structured outputs, validates the result, and returns JSON. Nothing is written to disk or a database.

> **Physical-device / TestFlight:** deploy to **Railway** (see [`docs/25_RAILWAY_GATEWAY.md`](../docs/25_RAILWAY_GATEWAY.md)). Terminate TLS at Railway. Local `npm run dev` remains a developer convenience only.

## Setup

```bash
cd gateway
cp .env.example .env
# edit .env — set OPENAI_API_KEY
# optional local: GATEWAY_SHARED_SECRET (required on Railway)

npm install
npm run dev          # tsx watch on PORT (default 8787)
# or
npm run build && npm start
```

Requires Node.js 20+.

## Environment

| Variable | Default | Notes |
|----------|---------|--------|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8787` | Listen port (Railway injects `PORT`) |
| `OPENAI_API_KEY` | _(required for understand)_ | Never commit; never log; never ship to iOS |
| `OPENAI_MODEL` | `gpt-5.6` | **GPT-5.6 Terra** initial product choice; replaceable |
| `GATEWAY_SHARED_SECRET` | _(empty locally)_ | Bearer token for `/v1/understand*` and `/v1/content-understand` — **not** the OpenAI key. **Required on Railway.** |
| `REQUEST_TIMEOUT_MS` | `60000` | Upstream + local abort timeout |
| `MAX_BATCH_SIZE` | `8` | Max members in `/v1/understand-batch` |
| `IMAGE_LONG_EDGE_MAX` | `1024` | Reject oversized client images |
| `SCHEMA_VERSION` | `screentidy-understanding-v2` | Contract version; mismatch → 422 |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Simple in-memory limiter window |
| `RATE_LIMIT_MAX_REQUESTS` | `30` | Max requests / window / client IP |

## Auth (MVP / TestFlight)

Cost-bearing routes require:

```http
Authorization: Bearer <GATEWAY_SHARED_SECRET>
```

`GET /health` stays public and never returns secrets.

**Security note:** A static token embedded in the iOS binary is only a basic quota-abuse barrier for Sprint 8 / TestFlight. It is **not** production-grade auth. Plan a later migration to App Attest / short-lived tokens / request signing.

## Endpoints

### `GET /health`

```json
{ "ok": true, "schemaVersion": "screentidy-understanding-v2", "contentSchemaVersion": "8.3a-content-v1", "modelConfigured": true }
```

`modelConfigured` is a boolean only — the API key is never revealed.

### `POST /v1/understand`

Single screenshot understanding for Collection resolver path (auth required when secret configured). May include eligible Collections.

### `POST /v1/understand-batch`

Up to `MAX_BATCH_SIZE` members (auth required when secret configured).

### `POST /v1/content-understand` (Sprint 8.3A DEBUG Lab)

Single-screenshot **content** understanding only. Requires image. **No** eligible Collections / Collection names. Schema `8.3a-content-v1`. Used by Visual Eval Multimodal Lab — not production organize.

## curl examples

Health:

```bash
curl -s http://localhost:8787/health | jq
```

Single (OCR-only) — include bearer when `GATEWAY_SHARED_SECRET` is set:

```bash
curl -s http://localhost:8787/v1/understand \
  -H "Authorization: Bearer ${GATEWAY_SHARED_SECRET}" \
  -H 'Content-Type: application/json' \
  -d '{
    "correlationId": "demo-001",
    "schemaVersion": "screentidy-understanding-v2",
    "ocrNormalized": "Park Hyatt Tokyo confirmation check-in Sep 12",
    "allowVisual": false,
    "eligibleCollections": [
      { "title": "Japan Trip", "keyEntities": ["Tokyo"], "keyTerms": ["hotel"] }
    ]
  }' | jq
```

## Privacy notes

- This gateway is **stateless**: request bodies live only in process memory for the request lifetime.
- Logs include only `correlationId`, HTTP status, latency, model, optional error code — never OCR/images/payloads.
- OpenAI retention follows the **deployed OpenAI account** that owns `OPENAI_API_KEY`.
- **Do not claim Zero Data Retention** unless ZDR (or equivalent) is verified for that account.
- Prefer TLS at the edge (Railway); do not expose cleartext publicly.

## Architecture reminders

- On-device **Collection Resolver remains sole authority** for reuse / create / Needs Review.
- Gateway only proposes structured understanding.
- Hosted HTTPS is the default physical-device path; local Mac LAN is optional DEBUG only.
