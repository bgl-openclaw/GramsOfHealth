// document-ai: the AI pass over one client document (owner decision 22 Oct 2026: Anthropic's API).
// POST { record_id } with the signed-in staff member's token. Admins and dietitians only.
//  1. Reads the record's document_text (already extracted in the browser) through the caller's own access (RLS).
//  2. Asks Claude for every item it can find, each with a quote copied exactly from the document.
//  3. Keeps only items whose quote really is in the document, drops repeats of items already found,
//     and saves the rest to client_document_facts as method 'ai' — always "Please check", never filed on their own.
//  4. Stores a summary on the record (ai_summary).
// Secrets: ANTHROPIC_API_KEY (set in Supabase → Edge Functions → Secrets). Optional AI_MODEL (default claude-sonnet-5-5).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const SECTIONS = ["client", "medicare", "care_team", "referral", "medication", "condition", "allergy", "measurement", "goal", "food_rule", "supplement", "note"];
const CLIENT_FIELDS = ["full_name", "date_of_birth", "sex", "phone", "email", "address_line", "suburb", "state", "postcode", "height_cm"];

const SYSTEM = `You read one document from an Australian dietitian practice's client file and list every item that belongs in the client's record.

Rules:
- Only items the document states. Never infer, guess, summarise or complete anything.
- Every item needs "quote": a short passage (at most 300 characters) copied EXACTLY, character for character, from the document, that shows the item. Items whose quote isn't found word for word in the document are thrown away.
- Dates as YYYY-MM-DD (Australian documents write day first). If a date is unclear, leave it out of the value.
- Leave out items you aren't sure belong to the client (for example the doctor's own phone number is care_team, not client).
- In a transcript, the client's own statements count: goals, foods they avoid, dislike or like, supplements, weights, symptoms (as notes).

Sections and their fields (field → value object):
- client: field is one of full_name, date_of_birth, sex (female|male), phone, email, address_line, suburb, state (NSW|VIC|QLD|WA|SA|TAS|ACT|NT), postcode, height_cm. Value: {"value": ...}.
- medicare: field "number". Value: {"number": "10 digits", "irn": 1-9 or null, "valid_to": "MM/YYYY" or null}.
- care_team: field "gp", "specialist" or "other". Value: {"role", "name", "specialty", "practice", "address", "phone", "fax", "email", "provider_number"}.
- referral: field "referral". Value: {"pathway": medicare_chronic|medicare_mental_health|ndis|dva|private_health|workers_comp|self|other, "plan_name" (as printed, e.g. GPMP), "referral_date", "reason", "sessions_approved", "valid_until", "referrer_name"}.
- medication: field "item". Value: {"name", "strength", "form", "dose", "frequency"}.
- condition: field "item". Value: {"condition", "noted_on", "status": current|past}.
- allergy: field "item". Value: {"kind": allergy|intolerance|nil_known, "substance", "reaction"}.
- measurement: field "weight_kg". Value: {"value": number, "measured_on"}.
- goal: field "item". Value: {"detail"}.
- food_rule: field "item". Value: {"food", "rule": avoid|dislike|like, "note"}.
- supplement: field "item". Value: {"name", "dose", "timing"}.
- note: field "item". Value: {"text"} — anything else useful to the dietitian (symptoms, plans, recommendations).

Record everything with the record_facts tool.`;

const TOOL = {
  name: "record_facts",
  description: "Record every item found in the document.",
  input_schema: {
    type: "object",
    properties: {
      facts: {
        type: "array",
        items: {
          type: "object",
          properties: {
            section: { type: "string", enum: SECTIONS },
            field: { type: "string" },
            value: { type: "object" },
            quote: { type: "string" },
          },
          required: ["section", "field", "value", "quote"],
        },
      },
    },
    required: ["facts"],
  },
};

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();
/** JSON with object keys sorted, so {a,b} and {b,a} compare equal (as jsonb does). */
const canon = (v: unknown): string => Array.isArray(v) ? `[${v.map(canon).join(",")}]`
  : v && typeof v === "object" ? `{${Object.keys(v as Record<string, unknown>).sort().map((k) => `${JSON.stringify(k)}:${canon((v as Record<string, unknown>)[k])}`).join(",")}}`
  : JSON.stringify(v);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, message: "POST only." }, 405);
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  // not set up is an answer, not a failure: the app shows it once and carries on
  if (!key) return json({ ok: false, code: "not_set_up", message: "The AI pass isn't set up yet: add ANTHROPIC_API_KEY as an Edge Function secret in Supabase." });
  const model = Deno.env.get("AI_MODEL") || "claude-sonnet-5-5";

  const auth = req.headers.get("Authorization") ?? "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: who } = await sb.auth.getUser();
  if (!who?.user) return json({ ok: false, message: "Please sign in." }, 401);
  const { data: me } = await sb.from("profiles").select("role").eq("id", who.user.id).single();
  if (!me || !["admin", "dietitian"].includes(me.role)) return json({ ok: false, message: "Only dietitians and admins can run the AI pass." }, 403);

  let recordId: string;
  try { recordId = (await req.json()).record_id; } catch { return json({ ok: false, message: "Send { record_id }." }, 400); }
  const { data: rec, error: recErr } = await sb.from("client_clinical_records").select("id, client_id, kind, document_text").eq("id", recordId).single();
  if (recErr || !rec) return json({ ok: false, message: "Document not found." }, 404);
  if (!rec.document_text || rec.document_text.trim().length < 20) return json({ ok: false, message: "This document has no text yet. Open it once so its text is read first." }, 400);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model, max_tokens: 8000,
      system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
      tools: [TOOL], tool_choice: { type: "tool", name: "record_facts" },
      messages: [{ role: "user", content: `Document type: ${rec.kind}\n\n<document>\n${rec.document_text}\n</document>` }],
    }),
  });
  if (!res.ok) return json({ ok: false, message: `The AI service refused the request (${res.status}). Try again later.` }, 502);
  const out = await res.json();
  const call = (out.content ?? []).find((c: { type: string }) => c.type === "tool_use");
  const suggested: Array<{ section: string; field: string; value: Record<string, unknown>; quote: string }> = call?.input?.facts ?? [];

  const text = norm(rec.document_text);
  const { data: existing } = await sb.from("client_document_facts").select("section, field, value").eq("record_id", rec.id);
  const seen = new Set((existing ?? []).map((f) => `${f.section}|${f.field}|${canon(f.value)}`));
  let droppedQuote = 0, droppedRepeat = 0, droppedShape = 0;
  const rows = [];
  for (const f of suggested) {
    if (!f || !SECTIONS.includes(f.section) || !/^[a-z_]{1,40}$/.test(f.field ?? "") || typeof f.value !== "object" || !f.quote) { droppedShape++; continue; }
    if (f.section === "client" && !CLIENT_FIELDS.includes(f.field)) { droppedShape++; continue; }
    const quote = String(f.quote).slice(0, 2000);
    if (!text.includes(norm(quote))) { droppedQuote++; continue; }
    const k = `${f.section}|${f.field}|${canon(f.value)}`;
    if (seen.has(k)) { droppedRepeat++; continue; }
    seen.add(k);
    rows.push({ record_id: rec.id, client_id: rec.client_id, section: f.section, field: f.field, value: f.value, quote,
                method: "ai", certainty: "check", check_reasons: ["suggested by the AI pass: check it against the document"], ai_model: model });
  }
  if (rows.length) {
    const { error } = await sb.from("client_document_facts").insert(rows);
    if (error) return json({ ok: false, message: error.message }, 400);
  }
  const summary = { model, at: new Date().toISOString(), suggested: suggested.length, kept: rows.length,
                    dropped_quote_not_in_document: droppedQuote, dropped_repeat: droppedRepeat, dropped_shape: droppedShape,
                    input_tokens: out.usage?.input_tokens ?? null, output_tokens: out.usage?.output_tokens ?? null };
  await sb.from("client_clinical_records").update({ ai_summary: summary }).eq("id", rec.id);
  return json({ ok: true, message: `${rows.length} suggestions to check.`, ...summary });
});
