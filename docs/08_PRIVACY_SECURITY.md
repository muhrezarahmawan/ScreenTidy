# ScreenTidy — Privacy & Security (MVP)

## Privacy Promise
- Screenshots remain in Apple Photos.  
- ScreenTidy stores organization **metadata on device** (Context Collections, Type Facets, Entities, OCR).  
- Organization into Context Collections is **always-on core product** — not a user toggle.  
- Any future **cloud/network** processing remains architecturally separable and may require its own disclosure; it is **ephemeral** — not a server-side photo or memory library.  
- No accounts, no cloud sync of the user’s library in MVP.

Match App Store privacy labels and in-app copy. Do **not** market as “fully on-device AI” if hybrid organization uses network processing.

---

## Sensitive inferences

Context titles may encode life intent (e.g. Visa Application, medical-adjacent docs). Treat metadata as sensitive:

- Stored in app sandbox DB  
- Sent only transiently during any future network organization requests (with required disclosure)  
- Avoid verbose logging of titles/OCR in production  
- Summaries/keywords should stay minimal  

---

## Data Classification

| Data | Storage | Leaves device? |
|------|---------|----------------|
| Screenshot bytes | Apple Photos | Transiently only if a future network organize path is used |
| UI thumbnails | App cache | Optional downscaled during organize |
| OCR / contexts / facets / entities | Local DB | OCR + thumb + context title list may be sent transiently if networked |
| Search index | Local DB | No |
| Analytics | Not in MVP | N/A |

---

## Cloud / network processing (Sprint 8 accuracy remediation)

1. Separate from always-on organization product capability  
2. Requires clear disclosure before any screenshot-derived payload leaves the device  
3. ScreenTidy-owned **stateless HTTPS gateway** holds provider credentials — the iOS app never embeds OpenAI keys  
4. Gateway must not persist images/OCR or own Collection state  
5. Small thumbnails only (long edge ≤ 1024, JPEG ~0.75 by default) — never full-res by default  
6. API keys only on gateway; timeouts, batch ceiling (8), schema versioning  
7. Provider training: OpenAI API data is **not** used for training by default; **Zero Data Retention is a separate account configuration** — do **not** claim ZDR unless the deployed OpenAI account has verified ZDR enabled. Document the real deployed retention setting in ops notes.  
8. Prefer on-device paths when consent declined / offline; UI copy emphasizes benefits, not an “AI on/off” preference for core organization  
9. Production logs must not contain raw OCR, images, or model payloads  

See `gateway/README.md` for setup and privacy configuration notes.  

---

## Local Security
Sandbox · scrubbed production logs · soft-removed items excluded from search · dual delete clarity  

---

## Destructive Actions
Remove from ScreenTidy ≠ Delete from Photos.  
Photos delete: always explicit confirm. No automatic Photos deletes.  
Undo applies to remove-from-app, not to confirmed Photos deletes.

---

## Threat Notes

| Threat | Mitigation |
|--------|------------|
| Open AI proxy abuse | Attest + rate limits + caps |
| Accidental Photos delete | Separate action + strong confirm |
| Prompt injection via OCR | Structured outputs + policy |
| Sensitive context title leakage via logs | Redact / no PII logs |
| Collection churn eroding trust | Resolver reuse + min reorganization |
| Stale index after Photos delete | Library observer |

---

## Nutrition Labels (direction)
If hybrid ships with image upload: disclose image data may be processed; not permanently stored by ScreenTidy; no account tracking in MVP. Finalize at submission against real gateway behavior.

---

## We do not (MVP)
Cloud photo backup · sell data · ads fingerprinting · require login for organization  
