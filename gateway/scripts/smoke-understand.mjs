/**
 * Minimal Railway / local gateway smoke tests (no image payload).
 *
 * Usage:
 *   ST_GW=https://….up.railway.app ST_TOK=… node scripts/smoke-understand.mjs
 */
const gw = (process.env.ST_GW || process.env.GATEWAY_URL || "").replace(/\/$/, "");
const tok = process.env.ST_TOK || process.env.GATEWAY_SHARED_SECRET || "";

if (!gw || !tok) {
  console.error("Set ST_GW and ST_TOK (or GATEWAY_URL / GATEWAY_SHARED_SECRET)");
  process.exit(2);
}

async function hit(path, init) {
  const res = await fetch(`${gw}${path}`, init);
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { status: res.status, body };
}

const health = await hit("/health");
console.log("A /health", health.status, JSON.stringify(health.body));

const single = await hit("/v1/understand", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${tok}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    correlationId: `smoke-single-${Date.now()}`,
    schemaVersion: "screentidy-understanding-v2",
    ocrNormalized: "Booking confirmation for Hotel Calton Paris 12–15 Mar",
    allowVisual: false,
    eligibleCollections: [],
  }),
});
console.log("B /v1/understand", single.status, JSON.stringify(single.body).slice(0, 500));

const batch = await hit("/v1/understand-batch", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${tok}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    correlationId: `smoke-batch-${Date.now()}`,
    schemaVersion: "screentidy-understanding-v2",
    allowVisual: false,
    eligibleCollections: [],
    members: [
      { localId: "a1", ocrNormalized: "Hotel Calton Paris booking" },
      { localId: "a2", ocrNormalized: "Paris trip itinerary Mar 12" },
    ],
  }),
});
console.log("C /v1/understand-batch", batch.status, JSON.stringify(batch.body).slice(0, 500));

const ok =
  health.status === 200 &&
  health.body?.ok === true &&
  single.status === 200 &&
  batch.status === 200;

process.exit(ok ? 0 : 1);
