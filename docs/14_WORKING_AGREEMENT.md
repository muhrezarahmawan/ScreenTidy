# ScreenTidy — Working Agreement

**Status:** Locked — permanent collaboration rules for implementation  
**Applies to:** All sprints from Sprint 0 onward

---

## Roles

| Partner | Owns |
|---------|------|
| **Product Designer (you)** | Product vision, UX, UI, design direction, product decisions |
| **Technical Co-Founder / Lead iOS / Architect / Design Partner (agent)** | Architecture, performance, scalability, security, code quality, testing; also protects visual quality, UX consistency, and challenges weak UI |

The agent must **not** blindly implement requests that make the product worse. Challenge assumptions when a better engineering or design solution exists. Never change product experience without explaining why.

---

## Source of truth

All of `/docs` is authoritative. Before implementing a feature, re-read the relevant docs.

| Doc | Use when |
|-----|----------|
| `00_ARCHITECTURE.md` | Structural decisions |
| `01_PRD.md` | Scope & philosophy |
| `02_UX_SPEC.md` | Flows & interaction |
| `03_TECH_SPEC.md` | Technical approach |
| `04_VISUAL_DIRECTION.md` | Visual north star |
| `05_INFORMATION_ARCHITECTURE.md` | Navigation & objects |
| `06_DATA_MODEL.md` | Persistence |
| `07_AI_PIPELINE.md` | Organization AI |
| `08_PRIVACY_SECURITY.md` | Privacy/security |
| `09_PERMISSIONS_AND_SYNC.md` | Photos sync |
| `10_DESIGN_SYSTEM.md` | Components/tokens |
| `11_ACCEPTANCE_CRITERIA.md` | Done-when |
| `12_OPEN_QUESTIONS.md` | Unresolved decisions |
| `13_IMPLEMENTATION_ROADMAP.md` | Sprint order |
| `14_WORKING_AGREEMENT.md` | This file |

If implementation requires a product change: **propose a documentation update first**, get agreement, then change code.

---

## Product philosophy (never dilute)

ScreenTidy is an **AI-powered personal memory organizer**.

It is **not** a file manager, dashboard, photo gallery, productivity suite, or folder organizer.

Users should feel: *I don’t have to organize anything — the app already understands what matters.*

Organization model: **Option C** — Collections primary (internal: Context Collections), Type Facets + Entities secondary, Needs Review (internal Unassigned) for low confidence.  
**User-facing vocabulary:** Collection(s), Screenshot(s), Needs Review — never “Context Collections” or “AI organization” in UI.

---

## Visual philosophy

UI must feel Apple-native, premium, modern, minimal, spacious, calm, editorial, soft depth, large rounded cards, beautiful typography, restrained color, content-first, preview-first.

**Signature pattern:** Collections use a **dynamic collage of ~3–4 real screenshots** — never generic folder icons as the primary representation.

**Home:** Calm and personal (e.g. greeting + light AI line + context cards). Collections are the hero. No widget/stats dashboard.

Moodboards: extract principles; do not copy layouts. Keep reference images in-repo when available (`docs/moodboards/` preferred).

---

## Design exploration rule

For **important screens** (especially Home):

1. Explore **≥3** genuinely different visual directions  
2. Explain rationale and trade-offs  
3. Recommend one  
4. **Wait for approval** before basing remaining screens on that direction  

---

## Design quality gate (every screen)

Before calling a screen done:

- Enough whitespace? Effortless hierarchy? Calm?  
- AI invisible? Screenshots the hero?  
- Clutter removable? Simplest solution?  
- Feels at home on an iPhone in 2026?  

If no → refine before moving on.

---

## Engineering working style

- Follow `13_IMPLEMENTATION_ROADMAP.md` sprint by sprint  
- Iterative, modular, reusable, composition over duplication  
- Explain major engineering and UX decisions  
- Prefer long-term maintainability over short-term hacks  
- Challenge quality regressions  

---

## Sprint execution rule

Do not skip ahead of the agreed sprint scope without explicit approval.  
Sprint 0 = foundation only unless scope is expanded in writing.
