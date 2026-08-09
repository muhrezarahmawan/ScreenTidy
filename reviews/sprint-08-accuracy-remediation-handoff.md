# SPRINT 8 ACCURACY REMEDIATION — COMPLETION HANDOFF

**Date:** 2026-08-09  
**Sprint 8 status:** **IMPLEMENTED BUT NOT ACCEPTED**  
**Sprint 9:** **NOT started**

Plan: `reviews/sprint-08-accuracy-improvement-plan.md` (**APPROVED**)

---

## What shipped

### Gateway (`gateway/`)
- Stateless Express/TS HTTPS service: `GET /health`, `POST /v1/understand`, `POST /v1/understand-batch`
- OpenAI Responses API + strict structured JSON schema
- Default model: `gpt-5.6` (GPT-5.6 Terra initial; swap via `OPENAI_MODEL`)
- No disk persistence of images/OCR; safe logging only

### iOS
- `CompositeUnderstandingProvider` → ephemeral gateway when consented + URL, else on-device stand-in
- `MultimodalImagePolicy` (1024 / 0.75), org OCR normalizer (Search raw untouched)
- Collection context profiles (`v8_accuracy_remediation`)
- Batch planner (≤ 8), multi-signal confidence, create corroboration
- `resolverVersion = 2`
- Resolver Inspector: gateway URL, scores, entities, batch, eval labels, Needs Review re-run

### Tests
**All ScreenTidyTests PASSED** (including corroboration + OCR normalizer cases).

---

## Gateway configuration

```bash
cd gateway
cp .env.example .env
# set OPENAI_API_KEY=
npm install
npm run dev   # http://127.0.0.1:8787
```

**Simulator:** default gateway `http://127.0.0.1:8787`  
**Physical device:** Settings → Developer → Resolver Inspector → set Gateway URL to Mac LAN IP, e.g. `http://192.168.1.20:8787`

iOS never holds OpenAI keys.

---

## Privacy configuration notes

- Explicit cloud disclosure before first upload; decline → no upload; app remains usable  
- Do **not** claim Zero Data Retention unless the deployed OpenAI account has verified ZDR  
- OpenAI API: data not used for training by default; retention/ZDR are separate controls — document the **actual** account setting  
- Gateway must not log OCR/images/payloads  
- ScreenTidy does not keep a cloud photo library  

---

## DEBUG evaluation workflow

1. Accept cloud understanding disclosure  
2. Start gateway; set device gateway URL if needed  
3. Settings → Developer → **Resolver Inspector**  
4. Optionally **Re-run Needs Review organization** (requeues eligible NR / failed; never user-locked)  
5. For sample rows, mark: Correct / Wrong Collection / Should NR / Wrong name  
6. Read aggregate DEBUG metrics at top of Inspector  
7. Inspect score components, normalized OCR, entities, batch IDs, reasons  

---

## Physical-device acceptance checklist (accuracy)

| ID | Case | Pass if |
|----|------|---------|
| A1 | Text-heavy boarding/hotel cluster | Context Collection (e.g. Japan Trip), not “Boarding Pass” |
| A2 | Image-only furniture/travel | Multimodal attempt; meaningful Collection or honest NR |
| A3 | Existing Japan Trip + Tokyo OCR/image | **REUSE** |
| A4 | Ambiguous meme/UI | Needs Review (not wrong file) |
| A5 | User Move lock | Never auto-overridden |
| A6 | Decline consent | No upload; Search/manual still work |
| A7 | Search regression | Known OCR still findable |
| A8 | Duplicate titles | No new title twins |
| A9 | Inspector explains decision | Scores + reason visible |
| A10 | Eval labels | Local stats update |

**Measured accuracy:** run baseline labels on stand-in/declined path if needed, then re-run with gateway multimodal and compare coverage / correct / wrong-file / NR rates. Do not claim success from NR shrinkage alone.

---

## Measured results (engineering)

| Metric | Value |
|--------|--------|
| Unit tests | **PASSED** |
| Device multimodal accuracy | **Pending physical-device eval** (requires gateway + OpenAI key + consent) |

Prior device baseline (stand-in): ~5% useful auto-file, high NR — root cause understanding quality.

---

## STOP

Accuracy remediation engineering complete for review.  
**Sprint 8 remains NOT ACCEPTED** until physical-device multimodal accuracy passes.  
**Do not start Sprint 9.**
