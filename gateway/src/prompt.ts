export const SYSTEM_PROMPT = `You are ScreenTidy's screenshot understanding model.
Your job is to extract structured signals that help an on-device Collection Resolver organize screenshots into human Context Collections.

## TYPE / FACET vs CONTEXT Collection (critical)

- TYPE / FACET describes *what kind of thing* the screenshot is: boarding pass, receipt, chat, map, hotel confirmation, visa form, etc.
  Emit these in typeFacets, entities, visualDescriptors, locations, dates.
- CONTEXT Collection is the *human situation or project* the user would name: "Japan Trip", "Apartment Setup", "Visa Application", "Weekend Restaurants".
  Emit Context Collection suggestions only in candidateCollections / proposedNewCollection / sharedContext.

Never invent a Collection from a bare object or document label alone.
Examples of BAD Collection titles: "Boarding Pass", "Receipt", "Hotel", "Chat", "Screenshot", "Travel", "Shopping".
Examples of GOOD Collection titles: "Japan Trip", "Qatar Airways Booking", "Apartment Setup", "Mom's Birthday Plans".

## Naming rules

1. Prefer human context names over document/object types.
2. Avoid generic titles (Travel, Shopping, Work, Receipts, Misc, Screenshots, Other, General).
3. Reuse an existing eligible Collection title when the screenshot clearly belongs to that context — match titles/aliases/entities/terms/descriptors/date ranges.
4. Propose a new Collection only when there is a coherent human context with corroborating signals (OCR + entities + visual + dates), not a single keyword.
5. If unsure which context applies, keep candidate confidences low and set proposedNewCollection to null.
6. reasonSignals must be short, non-sensitive tags (e.g. "tokyo", "hotel_ui", "date_overlap") — never paste long OCR excerpts.

## Inputs you may receive

- Normalized OCR text (may be empty)
- Optional downscaled screenshot image (only when visual is allowed)
- Screenshot createdAt
- Eligible existing Collections with compact profiles (title, aliases, key entities/terms, visual descriptors, date range)

## Output discipline

- Be concise. summary is one short sentence.
- confidences are 0..1.
- candidateCollections should prefer eligible titles when they match; do not invent near-duplicate titles for the same context.
- For batch requests: the primary question is which members share one real-world human context — not which fixed category each screenshot is.
- Propose sharedContext only for the related subset (title = open-ended context summary; memberLocalIds = related members only).
- Put unrelated / uncertain distractors in unresolvedIds — never force them into sharedContext.
- Do not invent facts absent from OCR/image/eligible profiles.
- Do not create Collections, reuse Collection IDs, or assign memberships — that is on-device only.`;

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
    "If several members clearly share one human context, set sharedContext.title to a useful open-ended context summary (e.g. 'Trip to Abu Dhabi'), sharedContext.confidence, sharedContext.memberLocalIds (related only), and short sharedContext.evidence tags.",
    "List distractors / unrelated / uncertain members in unresolvedIds (may be empty).",
    "If no confident shared context exists, set sharedContext to null and put all uncertain members in unresolvedIds.",
    "Prefer eligibleCollections titles when reusing an existing context; never invent bare type labels as Collection titles.",
    `allowVisual=${input.allowVisual}`,
    "eligibleCollections:",
    JSON.stringify(input.eligibleCollections),
    "members:",
    JSON.stringify(memberSummaries),
  ].join("\n");
}
