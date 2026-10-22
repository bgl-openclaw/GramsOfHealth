/**
 * Document reader: sorts a client document and reads the items in a GP or specialist letter or a discharge summary
 * into facts for client_document_facts (migration 0053). Runs in the browser; rules only (the AI pass is separate).
 *
 * Every fact quotes text exactly as it appears in the document (the database refuses anything else), carries the
 * section and field it belongs to, and is "sure" only when the pattern is unambiguous; otherwise "check" with reasons.
 * Pathology inside a letter is left to the results reader (packages/results-reader).
 */

export const DOC_READER_VERSION = "0.1.0";

export type DocKind = "pathology" | "dexa" | "gp_letter" | "specialist_letter" | "discharge_summary" | "transcript" | "letter" | "other";
export type Section = "client" | "medicare" | "care_team" | "referral" | "medication" | "condition" | "allergy" | "measurement" | "note";

export type Fact = {
  section: Section;
  field: string;
  value: Record<string, unknown>;
  quote: string;
  certainty: "sure" | "check";
  check_reasons: string[];
};

export type Classification = { kind: DocKind; contains: DocKind[]; reasons: string[] };

// ---------- sorting ----------

const SIGNS: Record<Exclude<DocKind, "letter" | "other">, RegExp[]> = {
  transcript: [/^webvtt/im, /^\s*(speaker\s*\d+|[A-Z][a-z]+(\s[A-Z][a-z]+)?)\s*:\s+\S/m, /^\s*\[?\d{1,2}:\d{2}(:\d{2})?\]?\s/m],
  pathology: [/\blab(?:oratory)?\s*ref(?:erence)?\b/i, /\breference\s+(interval|range)s?\b/i, /\bcollected\s*:/i, /\bspecimen\s+type\b/i, /\bpathology\b/i],
  dexa: [/\b(dxa|dexa)\b/i, /\bdensitometry\b/i, /\bt-?score\b/i, /\bbone mineral density\b/i, /\bbody composition\b/i],
  discharge_summary: [/\bdischarge summary\b/i, /\b(date of )?discharge( date)?\s*:/i, /\badmission( date)?\s*:/i],
  gp_letter: [/\bthank you for seeing\b/i, /\b(gpmp|gp management plan|team care arrangement|tca|gpccmp|chronic condition management|care plan)\b/i,
    /\bcurrent medications\b/i, /\bpast medical history\b/i],
  specialist_letter: [/\b(fracp|fracs|frcpa|franzcog|consultant)\b/i, /\b(endocrinolog|gastroenterolog|cardiolog|nephrolog|rheumatolog|neurolog|oncolog|respiratory physician|immunolog|surgeon)\w*/i,
    /\b(impression|diagnos[ie]s|recommendations?)\s*:/i, /^\s*dear\s+dr\b/im],
};

const FIELD_LABELS = new Set(["phone", "fax", "email", "abn", "dob", "re", "date", "sex", "name", "patient", "address", "medicare", "medicare number",
  "collected", "requested", "reported", "received", "birthdate", "laboratory", "your reference", "lab reference", "specimen type", "name of test",
  "allergies", "medications", "diagnoses", "diagnosis", "plan", "impression", "weight", "height", "provider", "mobile", "tel", "ref", "cc", "attention"]);

/** What kind of document this is, and what else it contains (a GP letter often has pathology attached). */
export function classifyDocument(text: string): Classification {
  const score = (k: keyof typeof SIGNS) => SIGNS[k].filter((r) => r.test(text)).length;
  const s = Object.fromEntries((Object.keys(SIGNS) as (keyof typeof SIGNS)[]).map((k) => [k, score(k)])) as Record<keyof typeof SIGNS, number>;
  // a conversation: a few speakers' labels repeating ("Dietitian: …", "Client: …"), not form fields ("Phone: …", "DOB: …")
  const labels = new Map<string, number>();
  for (const m of text.matchAll(/^\s*(speaker\s*\d+|[A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s*:\s+\S/gm)) {
    const label = m[1].toLowerCase();
    if (!FIELD_LABELS.has(label)) labels.set(label, (labels.get(label) ?? 0) + 1);
  }
  const top = [...labels.values()].sort((a, b) => b - a);
  const speakerLines = top.slice(0, 4).reduce((s, n) => s + n, 0);
  const conversation = top.length >= 2 && top.length <= 6 && top[0] >= 3 && top[1] >= 2 && speakerLines >= 6;
  const reasons: string[] = [];
  let kind: DocKind = "other";
  if (/^webvtt/im.test(text) || conversation) { kind = "transcript"; reasons.push(`${speakerLines} speaker lines`); }
  else if (s.discharge_summary >= 2) kind = "discharge_summary";
  else if (s.gp_letter >= 2) kind = "gp_letter";
  else if (s.specialist_letter >= 2) kind = "specialist_letter";
  else if (s.dexa >= 2) kind = "dexa";
  else if (s.pathology >= 2) kind = "pathology";
  else if (/^\s*(dear|re:)/im.test(text)) kind = "letter";
  if (kind !== "other") reasons.push(`looks like ${kind.replace("_", " ")}`);
  const contains = (["pathology", "dexa"] as const).filter((k) => k !== kind && s[k] >= 2);
  if (kind === "gp_letter" && s.specialist_letter >= 3) reasons.push("also reads like a specialist letter");
  return { kind, contains: [...contains], reasons };
}

// ---------- small parsers ----------

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };
function iso(d: number, m: number, y: number): string | null {
  if (y < 100) y += y > 40 ? 1900 : 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2100) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCDate() === d ? `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}` : null;
}
/** The first date in a string (day first), as YYYY-MM-DD. */
export function firstDate(s: string): string | null {
  let m = s.match(/(?<![\d.])(\d{1,2})([/-])(\d{1,2})\2(\d{2,4})(?![\d.])/);
  if (m) return iso(+m[1], +m[3], +m[4]);
  m = s.match(/\b(\d{1,2})(?:st|nd|rd|th)?[\s-]([A-Za-z]{3,9})[\s-,]+(\d{2,4})\b/);
  if (m && MONTHS[m[2].slice(0, 3).toLowerCase()]) return iso(+m[1], MONTHS[m[2].slice(0, 3).toLowerCase()], +m[3]);
  return null;
}

/** Medicare card number: 10 digits, first 2–6, check digit = weighted sum of the first 8 (1,3,7,9,…) mod 10. */
export function medicareValid(digits: string): boolean {
  if (!/^[2-6]\d{9}$/.test(digits)) return false;
  const w = [1, 3, 7, 9, 1, 3, 7, 9];
  return w.reduce((sum, wt, i) => sum + wt * +digits[i], 0) % 10 === +digits[8];
}

const PHONE = /\b(?:phone|ph|tel|telephone|mobile|mob)\.?\s*:?\s*((?:\+?61|0)[\d ()-]{7,15}\d)/i;
const FAX = /\bfax\.?\s*:?\s*((?:\+?61|0)?[\d ()-]{7,15}\d)/i;
const EMAIL = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/;
const STATES = "NSW|VIC|QLD|WA|SA|TAS|ACT|NT";
const PROVIDER = /^\s*(\d{6}[0-9A-Z][A-Z])\s*$/;
const SIGN_OFF = /^\s*(yours (faithfully|sincerely|truly)|kind regards|warm regards|best regards|regards|sincerely)\b/i;

function tidyPhone(s: string): string { return s.replace(/\s+/g, " ").trim(); }

/** "55 Example Ave, PANANIA. 2213" / "1 Example St, Exampletown NSW 2000" → parts (null when it isn't an address). */
export function parseAddress(s: string): { address_line: string; suburb: string; state: string | null; postcode: string } | null {
  const m = s.trim().match(new RegExp(`^(\\d[^,]*?),\\s*([A-Za-z][A-Za-z' -]*?)[.,]?\\s+(?:(${STATES})\\s*)?(\\d{4})\\.?$`, "i"));
  if (!m) return null;
  return { address_line: m[1].trim(), suburb: m[2].trim().replace(/\.$/, ""), state: m[3]?.toUpperCase() ?? null, postcode: m[4] };
}

const FORMS = ["prefilled syringe", "ear drops", "eye drops", "nasal spray", "modified release tablet", "tablet", "tablets", "capsule", "capsules",
  "syringe", "injection", "cream", "ointment", "inhaler", "puffer", "patch", "solution", "suspension", "sachet", "spray", "drops", "lozenge", "pen"];
const STRENGTH = /(\d+(?:[.,]\d+)?\s*(?:mg|mcg|micrograms?|g|ml|mL|units?|IU|%|elisa units)(?:\s*[;/]\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|mL|units?|%))*(?:\/\d*(?:\.\d+)?\s*(?:mL|ml))?)/i;

/** One medication as written in a letter. */
export function parseMedication(item: string): { name: string; strength: string | null; form: string | null; dose: string | null; frequency: string | null } | null {
  const text = item.trim().replace(/\.$/, "");
  const sm = text.match(STRENGTH);
  if (!sm || sm.index == null || sm.index === 0) return null;
  const name = text.slice(0, sm.index).trim();
  if (!/^[A-Za-z]/.test(name) || name.length < 2) return null;
  let rest = text.slice(sm.index + sm[0].length).trim();
  let form: string | null = null;
  for (const f of FORMS) {
    if (rest.toLowerCase().startsWith(f + " ") || rest.toLowerCase() === f) { form = rest.slice(0, f.length); rest = rest.slice(f.length).trim(); break; }
  }
  const dm = rest.match(/^(\d+(?:\.\d+)?\s*(?:tablets?|capsules?|syringes?|injections?|drops?|puffs?|sprays?|sachets?|mg|mcg|units?|ml|mL)\b)/i);
  const dose = dm ? dm[1] : null;
  if (dm) rest = rest.slice(dm[0].length).trim();
  return { name, strength: sm[0].trim(), form, dose, frequency: rest || null };
}

/** Splits a run-on medication paragraph into one item per medication ("… Friday. Doxycycline 100mg …"). */
export function splitMedications(line: string): string[] {
  return line.split(/\.\s+(?=[A-Z][\w'-]*(?:\s+[\w'-]+){0,3}\s+\d)/).map((s) => s.trim()).filter(Boolean);
}

// ---------- the letter ----------

type Heading = "medications" | "allergies" | "history" | "plan" | "other";
const HEADINGS: [Heading, RegExp][] = [
  ["medications", /^(?:(?:his|her|their|the patient's|current|regular|discharge)\s+)*(?:current\s+)?medications?(?:\s+(?:list|are|on discharge|include))?\s*(?:are)?\s*:?\s*$/i],
  ["allergies", /^(?:allerg(?:y|ies)(?:\s*\/\s*adverse (?:drug )?reactions)?|adverse (?:drug )?reactions|alerts?)\s*:?\s*/i],
  ["history", /^(?:past (?:medical )?history|medical history|pmhx?|active problems?|problem list|diagnos[ie]s|principal diagnosis|conditions)\s*:?\s*$/i],
  ["plan", /^(?:impression|assessment|plan|recommendations?|management|summary|follow[- ]up)\s*:?\s*/i],
  ["other", /^(?:social history|family history|immunisations?|investigations|results|examination|on examination)\s*:?\s*$/i],
];

function headingOf(line: string): Heading | null {
  for (const [h, r] of HEADINGS) if (r.test(line.trim())) return h;
  return null;
}

/** Reads a GP or specialist letter or a discharge summary. `text` is the document text exactly as stored. */
export function readLetter(text: string, kind: DocKind): Fact[] {
  const lines = text.split(/\r?\n/);
  const facts: Fact[] = [];
  const add = (f: Omit<Fact, "check_reasons" | "certainty"> & { certainty?: Fact["certainty"]; check_reasons?: string[] }) => {
    const key = `${f.section}|${f.field}|${JSON.stringify(f.value)}`;
    if (facts.some((x) => `${x.section}|${x.field}|${JSON.stringify(x.value)}` === key)) return;
    const reasons = f.check_reasons ?? [];
    facts.push({ ...f, certainty: f.certainty ?? (reasons.length ? "check" : "sure"), check_reasons: reasons });
  };

  // 1. the letterhead: lines before the letter's date (or the first "Dear" / "RE:")
  const firstBody = lines.findIndex((l) => /^\s*(dear|re:|patient:)/i.test(l) || (firstDate(l) && l.trim().length <= 20));
  const head = lines.slice(0, firstBody < 0 ? Math.min(8, lines.length) : firstBody);
  const sender: Record<string, string> = {};
  for (const l of head) {
    const t = l.trim();
    if (!t || /^_{3,}|^-{3,}/.test(t)) continue;
    if (!sender.practice && /[A-Za-z]{3}/.test(t) && !PHONE.test(t) && !EMAIL.test(t) && !/^\d/.test(t)) sender.practice = t;
    const ph = t.match(PHONE); if (ph && !sender.phone) sender.phone = tidyPhone(ph[1]);
    const fx = t.match(FAX); if (fx && !sender.fax) sender.fax = tidyPhone(fx[1]);
    const em = t.match(EMAIL); if (em && !sender.email) sender.email = em[0];
    if (/^\d+\s+\S/.test(t) && !sender.address) sender.address = t;
    else if (sender.address && !sender.address.includes(",") && new RegExp(`\\b(${STATES})?\\s*\\d{4}\\b`).test(t) && !PHONE.test(t)) sender.address += ", " + t;
  }

  // 2. the letter's date
  const dateLine = lines.find((l, i) => i >= Math.max(0, head.length - 1) && firstDate(l) && l.trim().length <= 24);
  const letterDate = dateLine ? firstDate(dateLine) : null;

  // 3. the patient
  let patientName: string | null = null;
  for (const l of lines) {
    const m = l.match(/^\s*(?:re|patient|name)\s*:\s*(.+?)\s*$/i);
    const candidate = m ? m[1].replace(/[\s,]+(dob|d\.o\.b\.?|date of birth|born)\b.*$/i, "").trim() : "";
    if (m && candidate && !/\d/.test(candidate)) {
      patientName = candidate;
      const bare = patientName.replace(/^(mr|mrs|ms|miss|mx|dr|master)\.?\s+/i, "").trim();
      const initialOnly = !/[a-z]{2}/i.test(bare.replace(/\b[A-Z]\b\.?/g, ""));
      add({ section: "client", field: "full_name", value: { value: bare }, quote: l.trim(),
            check_reasons: initialOnly ? ["only an initial is given"] : [] });
      break;
    }
  }
  const dobs = new Set<string>();
  for (const l of lines) {
    const m = l.match(/\b(?:dob|d\.o\.b\.?|date of birth|birthdate|born)\s*:?\s*([0-9]{1,2}[/-][0-9]{1,2}[/-][0-9]{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})/i);
    if (m) { const d = firstDate(m[1]); if (d) { dobs.add(d); add({ section: "client", field: "date_of_birth", value: { value: d }, quote: m[0] }); } }
    const sx = l.match(/\bsex\s*:\s*(F|M|female|male)\b/i);
    if (sx) add({ section: "client", field: "sex", value: { value: /^f/i.test(sx[1]) ? "female" : "male" }, quote: sx[0] });
    const mc = l.match(/\bmedicare(?:\s+(?:number|no\.?|card))?\s*:?\s*([\d][\d -]{6,14}\d)(?:\s*(?:irn|ref)?\s*[:-]?\s*(\d))?/i);
    if (mc) {
      const digits = mc[1].replace(/\D/g, "");
      const number = digits.length === 11 ? digits.slice(0, 10) : digits;
      const irn = digits.length === 11 ? +digits[10] : mc[2] ? +mc[2] : null;
      const ok = medicareValid(number);
      add({ section: "medicare", field: "number", value: { number, irn }, quote: mc[0].trim(),
            check_reasons: ok ? [] : ["the Medicare number fails its check digit (or isn't 10 digits)"] });
    }
  }
  if (dobs.size > 1) for (const f of facts) if (f.field === "date_of_birth") { f.certainty = "check"; f.check_reasons.push("different dates of birth in the document"); }

  // the patient's own contact block: the lines right after a line that is just the patient's name
  if (patientName) {
    const nameAt = lines.map((l, i) => (l.trim() === patientName ? i : -1)).filter((i) => i >= 0);
    for (const i of nameAt) {
      for (const l of lines.slice(i + 1, i + 4)) {
        const a = parseAddress(l);
        if (a) {
          add({ section: "client", field: "address_line", value: { value: a.address_line }, quote: l.trim() });
          add({ section: "client", field: "suburb", value: { value: a.suburb.replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\B\w/g, (c) => c.toLowerCase()) }, quote: l.trim() });
          add({ section: "client", field: "postcode", value: { value: a.postcode }, quote: l.trim() });
          if (a.state) add({ section: "client", field: "state", value: { value: a.state }, quote: l.trim() });
        }
        const ph = l.match(PHONE);
        if (ph) add({ section: "client", field: "phone", value: { value: tidyPhone(ph[1]) }, quote: ph[0].trim() });
      }
    }
  }
  const phones = facts.filter((f) => f.section === "client" && f.field === "phone");
  if (phones.length > 1) for (const f of phones) { f.certainty = "check"; f.check_reasons.push("more than one phone number for the client"); }

  // 4. the referral (GP letters)
  const bodyText = lines.join(" ");
  const pathway =
    /\b(mental health (?:care|treatment) plan|mhcp|mhtp)\b/i.exec(bodyText) ? { pathway: "medicare_mental_health", m: /\b(mental health (?:care|treatment) plan|mhcp|mhtp)\b/i.exec(bodyText)! }
    : /\b(gpccmp|gpmp|tca|team care arrangement|gp management plan|chronic (?:disease|condition) management(?: plan)?|cdm|epc|enhanced primary care)\b/i.exec(bodyText) ? { pathway: "medicare_chronic", m: /\b(gpccmp|gpmp|tca|team care arrangement|gp management plan|chronic (?:disease|condition) management(?: plan)?|cdm|epc|enhanced primary care)\b/i.exec(bodyText)! }
    : /\bndis\b/i.exec(bodyText) ? { pathway: "ndis", m: /\bndis\b/i.exec(bodyText)! }
    : /\bdva\b|veterans'? affairs/i.exec(bodyText) ? { pathway: "dva", m: /\bdva\b|veterans'? affairs/i.exec(bodyText)! }
    : null;
  const reasonLine = lines.find((l) => /thank you for seeing|referr(?:ing|al)\b.*\bfor\b/i.test(l));
  if (kind === "gp_letter" || pathway || reasonLine) {
    let reason: string | null = null;
    if (reasonLine) {
      // "Thank you for seeing <name> for an opinion and management of her dyslipidaemia under a GPMP."
      const tail = reasonLine.replace(/^.*?\bthank you for seeing\s+.+?\s+for\s+/i, "").replace(/^.*?\breferr(?:ing|al)\b.*?\bfor\s+/i, "");
      const r = tail.match(/^(?:an?\s+)?(?:opinion and management of|management of|review of|assessment of|advice (?:on|regarding))?\s*(?:(?:his|her|their)\s+)?(.+?)(?:\s+under\s+.*)?\.?\s*$/i);
      reason = r ? r[1].trim() : null;
    }
    const sessions = bodyText.match(/\b(\d{1,2})\s+(?:sessions|visits|services|consultations)\b/i);
    const reasons: string[] = [];
    if (!pathway) reasons.push("no referral pathway named");
    if (!letterDate) reasons.push("no letter date found");
    add({ section: "referral", field: "referral",
          value: { pathway: pathway?.pathway ?? "other", plan_name: pathway?.m[0] ?? null, referral_date: letterDate, reason,
                   sessions_approved: sessions ? +sessions[1] : null, referrer_name: null },
          quote: (reasonLine ?? pathway?.m[0] ?? "").trim(), check_reasons: reasons });
  }

  // 5. sections: medications, allergies, history, plan
  let current: Heading | null = null;
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const t = raw.trim();
    if (!t) continue;
    if (SIGN_OFF.test(t) || /^\s*(dear|re:)\b/i.test(t)) { current = null; continue; }
    const h = headingOf(t);
    if (h) {
      current = h;
      // "Allergies: Nil known." / "Diagnosis: Coeliac disease" on the same line
      const after = t.replace(HEADINGS.find(([k]) => k === h)![1], "").trim();
      if (!after) continue;
      readSectionLine(h, after);
      continue;
    }
    if (/^(medications?|allergies|past medical history)\b/i.test(t) === false && /[:]$/.test(t) && t.length < 60) { current = null; continue; }
    if (current) readSectionLine(current, t);
  }
  function readSectionLine(h: Heading, t: string) {
    if (h === "medications") {
      for (const item of splitMedications(t)) {
        const m = parseMedication(item);
        if (m) add({ section: "medication", field: "item", value: m, quote: item.replace(/\.$/, "") });
        else if (/[A-Za-z]{3}/.test(item)) add({ section: "medication", field: "item", value: { name: item.replace(/\.$/, "") }, quote: item.replace(/\.$/, ""), check_reasons: ["couldn't separate the name, strength and dose"] });
      }
    } else if (h === "allergies") {
      if (/\b(nil|none|no)\s+(known|allerg)|^nkda\b|^nil\.?$/i.test(t)) add({ section: "allergy", field: "item", value: { kind: "nil_known" }, quote: t });
      else for (const part of t.split(/[;,]\s*/)) {
        const m = part.match(/^([A-Za-z][A-Za-z '-]+?)\s*(?:[-–:(]\s*(.+?)\)?)?\.?$/);
        if (m) add({ section: "allergy", field: "item", value: { kind: /intoleran/i.test(part) ? "intolerance" : "allergy", substance: m[1].trim(), reaction: m[2]?.trim() ?? null }, quote: part.trim() });
      }
    } else if (h === "history") {
      const dm = t.match(/^(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4})\s+(.+)$/);
      const condition = (dm ? dm[2] : t).replace(/^[-•*\d.)\s]+/, "").replace(/\.$/, "").trim();
      if (condition.length >= 3) add({ section: "condition", field: "item",
        value: { condition, noted_on: dm && dm[1].length > 4 ? firstDate(dm[1]) : null }, quote: t.replace(/\.$/, "") });
    } else if (h === "plan") {
      add({ section: "note", field: "plan", value: { text: t }, quote: t, check_reasons: ["recommendations are filed by a person"] });
    }
  }

  // 6. the author: the name after the sign-off, with a provider number on the next lines
  const so = lines.findIndex((l) => SIGN_OFF.test(l));
  if (so >= 0) {
    const after = lines.slice(so + 1, so + 6).map((l) => l.trim()).filter(Boolean);
    const nameLine = after.find((l) => /^(dr|prof|professor|a\/prof|associate professor)\.?\s+[A-Z]/i.test(l) || /^[A-Z][a-z]+ [A-Z][a-z]+/.test(l));
    if (nameLine) {
      const provider = after.map((l) => l.match(PROVIDER)?.[1]).find(Boolean) ?? null;
      const specialty = (bodyText.match(/\b(endocrinologist|gastroenterologist|cardiologist|nephrologist|rheumatologist|neurologist|oncologist|respiratory physician|immunologist|general physician|surgeon)\b/i) ?? [])[1] ?? null;
      const role = kind === "gp_letter" ? "gp" : kind === "specialist_letter" ? "specialist" : "other";
      const name = nameLine.replace(/\s+(mbbs|fracp|fracgp|fracs|md|phd|bsc|ma)\b.*$/i, "").trim();
      add({ section: "care_team", field: role, quote: nameLine,
            value: { role, name, specialty: role === "specialist" ? specialty : null, practice: sender.practice ?? null,
                     address: sender.address ?? null, phone: sender.phone ?? null, fax: sender.fax ?? null, email: sender.email ?? null,
                     provider_number: provider },
            check_reasons: role === "other" ? ["not sure whether this is the GP or a specialist"] : [] });
      for (const f of facts) if (f.section === "referral") f.value.referrer_name = name;
    }
  }

  // 7. measurements written in the letter
  for (const l of lines) {
    const w = l.match(/\bweight\s*:?\s*(\d{2,3}(?:\.\d)?)\s*kg\b/i);
    if (w) add({ section: "measurement", field: "weight_kg", value: { value: +w[1], measured_on: letterDate }, quote: w[0],
                 check_reasons: letterDate ? [] : ["no date for this weight"] });
    const h = l.match(/\bheight\s*:?\s*(\d{3}(?:\.\d)?)\s*cm\b/i);
    if (h) add({ section: "client", field: "height_cm", value: { value: +h[1] }, quote: h[0] });
  }
  return facts;
}
