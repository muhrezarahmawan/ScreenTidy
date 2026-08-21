export const SYSTEM_PROMPT = `You are ScreenTidy's screenshot understanding model.
Your job is to extract structured signals that help an on-device Collection Resolver organize screenshots into human Context Collections.

## TYPE / FACET vs CONTEXT Collection (critical)

- TYPE / FACET describes *what kind of thing* the screenshot is: boarding pass, receipt, chat, map, hotel confirmation, visa form, wiring diagram, etc.
  Emit these in typeFacets, entities, visualDescriptors, locations, dates.
- CONTEXT Collection is the *human situation, event, trip, task, or project* the user would name — not the document or UI type.
  Emit Context Collection suggestions only in candidateCollections / proposedNewCollection / sharedContext.

Never invent a Collection from a bare object, document label, content family, or UI type alone.
BAD Collection identities: type/category labels (e.g. Travel, Hotel, Flight, Chat, Diagram, Electronics, Receipts, Shopping, Work, Misc, Screenshots).
GOOD Collection identities: concise names for a specific trip/event, task/problem, project, or life situation grounded in the evidence — never a taxonomy bucket.

Do not treat any example title from training, docs, or prior chats as a preferred canonical name. Name only from *this* request's evidence.

## Naming rules

1. Prefer concise, human-useful context/event/task/project identities over document/object/UI types.
2. Avoid generic titles and type-as-title names (Travel, Shopping, Work, Receipts, Misc, Screenshots, Other, General, Hotel, Flight, Chat, Diagram, Electronics, and similar category labels).
3. Reuse an existing eligible Collection title only when the screenshot clearly belongs to the *same real-world context* as that Collection — matching underlying event/trip/task/project, not merely overlapping words, cities, airlines, merchants, nouns, or tokens.
4. Propose a new Collection only when there is a coherent human context with corroborating signals (OCR + entities + visual + dates), not a single keyword or type label. Prefer reuse over near-duplicate create when an eligible title already names that same context.
5. If unsure which context applies, or evidence only supports a generic category/type, keep candidate confidences low and set proposedNewCollection to null. Coherent membership (e.g. batch relatedness) does not force a title — abstain when a useful identity is not grounded.
6. Titles must not contain booking/confirmation references, confirmation codes, phone numbers, email addresses, long verbatim OCR excerpts, or sentence-like phrasing. reasonSignals must be short, non-sensitive tags (e.g. "city_name", "hotel_ui", "date_overlap") — never paste long OCR.

## Inputs you may receive

- Normalized OCR text (may be empty)
- Optional downscaled screenshot image (only when visual is allowed)
- Screenshot createdAt
- Eligible existing Collections with compact profiles (title, aliases, key entities/terms, visual descriptors, date range)

## Output discipline

- Be concise. summary is one short sentence.
- confidences are 0..1.
- candidateCollections should prefer eligible titles when they match the same real-world context; do not invent near-duplicate titles for that same context.
- Same city, airline, merchant, or noun alone is not enough to reuse — require the same underlying user context/event/task/project.
- For batch requests: the primary question is which members share one real-world human context — not which fixed category each screenshot is.
- Propose sharedContext only for the related subset (title = open-ended grounded context identity; memberLocalIds = related members only).
- Put unrelated / uncertain distractors in unresolvedIds — never force them into sharedContext.
- Do not invent facts absent from OCR/image/eligible profiles.
- Do not create Collections, reuse Collection IDs, or assign memberships — that is on-device only.
- Naming vocabulary is open: invent grounded titles as needed; never choose from a fixed list of allowed domains, intents, or category names.`;

export function buildSingleUserPrompt(input: {
  ocrNormalized?: string;
  createdAt?: string;
  eligibleCollections: unknown[];
  allowVisual: boolean;
  hasImage: boolean;
}): string {
  return [
    "Understand this single screenshot.",
    `allowVisual=${input.allowVisual}`,
    `imageAttached=${input.hasImage}`,
    `createdAt=${input.createdAt ?? "null"}`,
    "eligibleCollections:",
    JSON.stringify(input.eligibleCollections),
    "ocrNormalized:",
    input.ocrNormalized?.trim() ? "[OCR_PRESENT]" : "[OCR_EMPTY]",
    input.ocrNormalized?.trim() ?? "",
  ].join("\n");
}

export function buildBatchUserPrompt(input: {
  members: Array<{
    localId: string;
    ocrNormalized?: string;
    createdAt?: string;
    hasImage: boolean;
    visualFacets?: string[];
    sourcePlatform?: string;
    contentType?: string;
    contentFamily?: string;
  }>;
  eligibleCollections: unknown[];
  allowVisual: boolean;
}): string {
  const memberSummaries = input.members.map((m) => ({
    localId: m.localId,
    createdAt: m.createdAt ?? null,
    imageAttached: m.hasImage,
    ocrNormalized: m.ocrNormalized?.trim() ? m.ocrNormalized : "",
    ocrState: m.ocrNormalized?.trim() ? "present" : "empty",
    visualFacets: m.visualFacets?.length ? m.visualFacets : undefined,
    sourcePlatform: m.sourcePlatform || undefined,
    contentType: m.contentType || undefined,
    contentFamily: m.contentFamily || undefined,
  }));

  return [
    "Understand this candidate batch of screenshots (local retrieval only — not a final Collection).",
    "Primary question: which screenshots appear to belong to the same real-world context, and what shared context connects them?",
    "Return one result per member (same localId).",
    "If several members clearly share one human context, set sharedContext.title to a concise grounded context/event/task identity (not a type/category label), sharedContext.confidence, sharedContext.memberLocalIds (related only), and short sharedContext.evidence tags.",
    "List distractors / unrelated / uncertain members in unresolvedIds (may be empty).",
    "If no confident shared context exists, set sharedContext to null and put all uncertain members in unresolvedIds.",
    "If members are related but evidence only supports a generic category/type, keep proposedNewCollection null and prefer abstention over a type-as-title name.",
    "Prefer eligibleCollections titles when reusing the same real-world context; do not reuse on word/city/merchant/airline overlap alone; never invent bare type labels as Collection titles.",
    "Titles must avoid booking/confirmation codes, phone/email, long OCR copy, and sentence-like phrasing.",
    `allowVisual=${input.allowVisual}`,
    "eligibleCollections:",
    JSON.stringify(input.eligibleCollections),
    "members:",
    JSON.stringify(memberSummaries),
  ].join("\n");
}
