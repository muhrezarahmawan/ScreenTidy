# Railway deployment — ScreenTidy AI Gateway

**Sprint 8 status:** IMPLEMENTED BUT NOT ACCEPTED  
**Phase:** **P0 — Hosted HTTPS multimodal baseline** (Architecture C)  
**Purpose:** Physical iPhone testing without Mac LAN.  
**Not sufficient alone** for Sprint 8 acceptance — product-quality organization still required via later phases.

Canonical intelligence plan: `reviews/intelligence-architecture-multisignal-proposal.md`

## Architecture

```
Physical iPhone
  → HTTPS ScreenTidy Gateway (Railway)
  → OpenAI multimodal (server-side key only)
  → structured JSON
  → on-device Collection Resolver (sole authority)
  → GRDB → UI
```

Apple Vision remains an approved **follow-on** (`reviews/vision-visual-signals-research-proposal.md`) and is **not** part of this deploy.

## What you deploy

Folder: `gateway/` (existing Express/TypeScript service).

- Stateless (no DB; no Collection mutations)
- `GET /health` — public, no secrets
- `POST /v1/understand` + `/v1/understand-batch` — require `Authorization: Bearer <GATEWAY_SHARED_SECRET>`
- Body size limit 8mb; simple in-memory rate limit; schema validation before OpenAI

## Environment variables (Railway)

| Variable | Required | Notes |
|----------|----------|--------|
| `OPENAI_API_KEY` | **Yes** | Never commit; never ship to iOS |
| `GATEWAY_SHARED_SECRET` | **Yes on Railway** | MVP/TestFlight bearer token — **not** the OpenAI key |
| `OPENAI_MODEL` | No | Default `gpt-5.6` |
| `PORT` | Auto | Railway injects |
| `HOST` | No | Default `0.0.0.0` |
| `REQUEST_TIMEOUT_MS` | No | Default `60000` |
| `MAX_BATCH_SIZE` | No | Default `8` |
| `IMAGE_LONG_EDGE_MAX` | No | Default `1024` |
| `SCHEMA_VERSION` | No | Default `screentidy-understanding-v2` |
| `RATE_LIMIT_WINDOW_MS` | No | Default `60000` |
| `RATE_LIMIT_MAX_REQUESTS` | No | Default `30` / window / IP |

Generate a secret:

```bash
openssl rand -hex 32
```

## Deploy steps (Railway dashboard)

1. Create a Railway project → **New** → **Deploy from GitHub** (or empty + local CLI later).
2. Set **Root Directory** to `gateway` (important).
3. Railway should detect `Dockerfile` / `railway.toml`.
4. Variables → add the table above (`OPENAI_API_KEY`, `GATEWAY_SHARED_SECRET`, optional `OPENAI_MODEL`).
5. Generate a public HTTPS domain (Settings → Networking → Public Domain) → copy `https://….up.railway.app`.
6. Confirm deploy healthy: open `https://<host>/health`.

### CLI alternative (optional)

```bash
npm i -g @railway/cli
railway login
cd gateway
railway init
railway variables set OPENAI_API_KEY=… GATEWAY_SHARED_SECRET=… OPENAI_MODEL=gpt-5.6
railway up
railway domain
```

## Verify after deploy

Health (no auth):

```bash
curl -sS https://<host>/health
# {"ok":true,"schemaVersion":"…","modelConfigured":true}
```

Understand (auth required) — OCR-only smoke, no screenshot binary:

```bash
curl -sS https://<host>/v1/understand \
  -H "Authorization: Bearer $GATEWAY_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "correlationId": "railway-smoke-001",
    "schemaVersion": "screentidy-understanding-v2",
    "ocrNormalized": "Park Hyatt Tokyo confirmation check-in Sep 12",
    "allowVisual": false,
    "eligibleCollections": [{ "title": "Japan Trip", "keyEntities": ["Tokyo"] }]
  }'
```

Expect JSON with `candidateCollections` / entities — **not** only `/health`.

## iOS configuration

1. Copy `ScreenTidy/Config/Secrets.xcconfig.example` → `ScreenTidy/Config/Secrets.xcconfig` (gitignored).
2. Set:

```
SCREENTIDY_GATEWAY_BASE_URL = https:/$()/YOUR_HOST.up.railway.app
SCREENTIDY_GATEWAY_TOKEN = <same as GATEWAY_SHARED_SECRET>
```

3. Rebuild the app. Resolver Inspector **Active URL** / **Provider resolves to** should show the HTTPS host.
4. DEBUG Gateway field remains an **optional override** (e.g. local Mac). Clear override to use hosted default.

**Do not** put `OPENAI_API_KEY` in xcconfig, Info.plist, or source.

## Auth strength (documented)

Embedding `GATEWAY_SHARED_SECRET` in the iOS binary is **only** an MVP/TestFlight quota-abuse barrier. It is **not** strong production authentication.

Later migrate toward: App Attest / DeviceCheck, short-lived server-issued tokens, or signed requests.

## Privacy / retention

- Gateway does not persist OCR/images/Collections.
- Logs: correlationId, status, latency, model, error code only.
- OpenAI retention follows the **deployed OpenAI account** configuration.
- **Do not claim Zero Data Retention** unless ZDR (or equivalent) is verified for that account.
- Cloud understanding still requires in-app consent before upload.

## Local vs hosted

| Mode | When |
|------|------|
| Hosted HTTPS (default for device) | Physical iPhone / TestFlight Sprint 8 |
| Local `npm run dev` | Simulator / optional Mac LAN DEBUG override |
| DEBUG URL field | Temporary override only |

## Rotate secrets

1. Generate new `GATEWAY_SHARED_SECRET` on Railway.
2. Update iOS `Secrets.xcconfig` token to match.
3. Redeploy app.
4. Optionally rotate `OPENAI_API_KEY` in Railway only (never on device).

## Cost note

Railway ~$5/mo hobby class; **OpenAI usage dominates** during eval.
