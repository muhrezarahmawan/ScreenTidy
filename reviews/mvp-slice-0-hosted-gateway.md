# Slice 0 — Hosted gateway deploy checklist

**Status:** 🔵 BLOCKED on Railway account login (CLI not installed / not authenticated in this environment)  
**Goal:** Physical iPhone uses hosted HTTPS by default (no Mac LAN / Terminal dependency).

## Why blocked here

- `railway` CLI is not installed in the agent environment
- No existing `Secrets.xcconfig` with a real Railway host
- Deploy requires your Railway login + OpenAI key on Railway only

## Exact steps (you run once)

```bash
# 1) Install + login
npm i -g @railway/cli
railway login

# 2) Deploy gateway/
cd gateway
railway init          # or link existing project
railway variables set OPENAI_API_KEY="<from gateway/.env or OpenAI dashboard>"
railway variables set GATEWAY_SHARED_SECRET="$(openssl rand -hex 32)"
# optional: OPENAI_MODEL=gpt-5.6
railway up
railway domain        # copy https://….up.railway.app

# 3) Health
curl -sS https://<host>/health
# expect: {"ok":true,...,"modelConfigured":true}
```

## Wire iOS (Secrets.xcconfig)

```bash
cp ScreenTidy/Config/Secrets.xcconfig.example ScreenTidy/Config/Secrets.xcconfig
```

Edit `Secrets.xcconfig` (gitignored):

```
SCREENTIDY_GATEWAY_BASE_URL = https:/$()/<YOUR_HOST>.up.railway.app
SCREENTIDY_GATEWAY_TOKEN = <same as GATEWAY_SHARED_SECRET>
```

Rebuild the app. Confirm **Settings → Developer → Resolver Inspector**:
- Active gateway URL is the HTTPS Railway host (not `127.0.0.1`)
- Health probe succeeds
- Clear any DEBUG LAN override unless intentionally testing Mac gateway

## Stop condition

Slice 0 is done only when the **physical iPhone** can reach `https://…/health` without Mac Terminal / same Wi‑Fi LAN gateway.

Mac LAN (`0.0.0.0:8787`) remains DEBUG override only.
