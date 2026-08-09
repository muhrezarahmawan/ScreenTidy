# ScreenTidy — Open Questions & Decision Log

## Locked philosophy (2026-08-08)

> ScreenTidy is an AI-powered personal memory organizer that understands the context and intent behind screenshots, then organizes them the way a thoughtful human assistant would.

**Option C locked:** Context Collections (primary) · Type Facets (secondary) · Entities · Unassigned · reuse-before-create · Home promotion threshold · hybrid ephemeral AI · SQLite+FTS · iOS 17+ · dual delete · no auth/analytics/IAP.

Supersedes fixed-taxonomy-as-primary-Home decisions.

---

## Decision Log

| Topic | Decision |
|-------|----------|
| Product positioning | Personal memory organizer — not AI folder/taxonomy product |
| Primary IA | Dynamic Context Collections |
| Secondary | Type Facets + Entities |
| Low confidence | Unassigned |
| Reuse | Always prefer existing context before create |
| Home visibility | Threshold (default 3) or pinned |
| Local DB | SQLite + FTS5 |
| iOS | 17+ |
| AI payload | OCR + small thumb + minimal metadata (+ existing titles) |
| Cleanup | Old 6 months · pHash duplicates · AI dates when possible |
| Delete | Dual path; Photos always confirmed; Undo for remove-from-app |

---

## Remaining unresolved (before / during early implementation)

### BLOCKER — Resolve preferred defaults

#### OQ-1. Home promotion threshold
Default **3** — confirm or change?

#### OQ-2. Confidence thresholds
Proposed: accept attach ≥ **0.55**; create new context ≥ **0.75**; below accept → Unassigned. Confirm?

#### OQ-3. Title similarity / reuse matching
MVP: normalized exact + alias table only, **or** also fuzzy/embedding similarity?  
Recommendation: exact + alias + simple normalized fuzzy (edit distance) in MVP; embeddings later.

#### OQ-4. Multi-context membership on Home ranking
If a screenshot is in Japan Trip + Qatar Airways, both gain activity — OK? Confirm.

#### OQ-5. Should Entities ever auto-promote to Context Collections?
e.g. repeated “Qatar Airways” entity → context.  
Recommendation: **allow in AI titles**, but no separate automatic entity→collection job in MVP beyond model proposals.

#### OQ-6. Facet vocabulary final list
IA proposes a starter set — product lock exact keys/labels?

#### OQ-7. Search placeholder copy
“Search memories” vs “Search screenshots”?

#### OQ-8. Onboarding exit
**Resolved (Sprint 2 / D-021):** User may skip import wait during organizing. Photos access is **mandatory** — Don’t Allow → recovery with Enable Photos Access / Exit ScreenTidy (no Continue without Photos). Exit leaves onboarding incomplete.

#### OQ-9. Favorites
App-only (recommended) vs Photos favorite sync?

#### OQ-10. AI insight line on context cards
Strong signals only vs cut for calmness?

#### OQ-11. Archive vs delete Context Collection
Confirm archive = hide; delete collection = remove memberships only (never Photos).

#### OQ-12. User contexts + AI attach
Keep **AI auto-attach to user_context OFF** in MVP?

#### OQ-13. Existing context list size in AI payload
How many titles sent (e.g. pinned + 20 recent)? Privacy vs reuse quality tradeoff.

#### OQ-14. Local DB in iCloud device backup
Allow default backup (recommended) vs exclude?

#### OQ-15. Gateway host + LLM vendor
Ops — must meet ephemeral + Attest requirements.

---

## Consistency notes (architect)

Watch for copy regressions that say “classify into categories/folders/taxonomy Home.”  
Canonical terms: **Context Collection**, **Type Facet**, **Entity**, **Unassigned**, **organize** (prefer over “classify” in user-facing copy).  
Engineering may still say “classification run” internally → prefer **OrganizationRun** in schema (docs updated).

---

## Ready for implementation?

**Nearly.** Confirm **OQ-1, OQ-2, OQ-3, OQ-6, OQ-12** at minimum; others can default to recommendations during build.
