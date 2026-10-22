/**
 * Results reader: finds blood test values in the text of a pathology report.
 * Runs in the browser; nothing leaves the device. The app supplies the PDF's text items (pdf.js getTextContent)
 * and the marker list (clinical_markers); this returns one row per value, ready for client_result_values.
 *
 * A value is "sure" only when every rule holds (docs/RESULTS-READER-PLAN.md):
 *   1 read from the PDF's own text (photos/scans: always "check")
 *   2 the test name matches a marker name or a name labs print for it
 *   3 the unit is the marker's unit, or one with a known exact conversion
 *   4 the number is clean (no limit sign, no stray characters, one value on the line)
 *   5 it is inside the marker's plausibility limits
 *   6 the lab's range and H/L flag agree with the number
 *   7 one collection date was found on the report
 * Anything else is "check", with the reasons listed.
 */

export const READER_VERSION = "0.1.0";

export type TextItem = { str: string; x: number; y: number; page: number; height?: number };
export type Line = { page: number; y: number; text: string; cells: { text: string; x: number }[] };

export type ReaderMarker = {
  code: string;
  name: string;
  unit: string | null;
  /** Names and abbreviations labs print (the marker's own name is always included). */
  names?: string[];
  /** Printed units with the factor to the marker's unit (value × factor). The marker's own unit is factor 1. */
  units?: { unit: string; factor: number }[];
  plausibleLow?: number | null;
  plausibleHigh?: number | null;
};

export type ReadValue = {
  marker_code: string | null;
  name_as_printed: string;
  value: number | null;
  value_text: string;
  unit_as_printed: string | null;
  value_std: number | null;
  lab_low: number | null;
  lab_high: number | null;
  lab_range_text: string | null;
  lab_flag: "H" | "L" | "HH" | "LL" | "*" | null;
  measured_on: string | null;
  page: number;
  line_text: string;
  method: "text" | "ocr";
  certainty: "sure" | "check";
  check_reasons: string[];
};

export type ReadResult = {
  reader_version: string;
  method: "text" | "ocr";
  measured_on: string | null;
  date_note: string | null;
  values: ReadValue[];
  pages: number;
  sure: number;
  please_check: number;
  unmatched: number;
};

// ---------- text items → lines ----------

/** pdf.js text content → TextItems (structural, so this package doesn't depend on pdf.js). */
export function itemsFromPdfJs(page: number, content: { items: Array<{ str?: string; transform?: number[]; height?: number }> }): TextItem[] {
  return content.items
    .filter((i) => typeof i.str === "string" && i.str.trim() !== "" && Array.isArray(i.transform))
    .map((i) => ({ str: i.str as string, x: (i.transform as number[])[4], y: (i.transform as number[])[5], page, height: i.height }));
}

/** Groups items into lines (same page, y within half a line height), left to right. */
export function toLines(items: TextItem[]): Line[] {
  const byPage = new Map<number, TextItem[]>();
  for (const it of items) byPage.set(it.page, [...(byPage.get(it.page) ?? []), it]);
  const lines: Line[] = [];
  for (const [page, its] of [...byPage.entries()].sort((a, b) => a[0] - b[0])) {
    const sorted = [...its].sort((a, b) => b.y - a.y || a.x - b.x);
    let current: TextItem[] = [];
    let y = Number.NaN;
    const flush = () => {
      if (!current.length) return;
      const cells = [...current].sort((a, b) => a.x - b.x).map((c) => ({ text: c.str.trim(), x: c.x })).filter((c) => c.text);
      lines.push({ page, y, text: cells.map((c) => c.text).join(" ").replace(/\s+/g, " ").trim(), cells });
      current = [];
    };
    for (const it of sorted) {
      const tol = Math.max(2, (it.height ?? 8) * 0.5);
      if (current.length && Math.abs(it.y - y) > tol) flush();
      if (!current.length) y = it.y;
      current.push(it);
    }
    flush();
  }
  return lines;
}

/** For tests and plain text: one line per row; cells split on two or more spaces or tabs. */
export function linesFromText(text: string, page = 1): Line[] {
  return text.split(/\r?\n/).map((row, i) => {
    const parts = row.split(/\t| {2,}/).map((s) => s.trim()).filter(Boolean);
    return { page, y: -i, text: parts.join(" "), cells: parts.map((t, j) => ({ text: t, x: j * 100 })) };
  }).filter((l) => l.text);
}

// ---------- normalising ----------

export function normName(s: string): string {
  return s.toLowerCase().replace(/[µμ]/g, "u").replace(/[^a-z0-9%]+/g, " ").replace(/\s+/g, " ").trim();
}
export function normUnit(s: string): string {
  return s.toLowerCase().replace(/[µμ]/g, "u").replace(/\s+/g, "").replace(/\^|\*/g, "").replace(/²/g, "2").replace(/iu\//g, "u/")
    .replace(/^mu\//, "mu/");
}

const KNOWN_UNITS = ["mmol/l", "umol/l", "nmol/l", "pmol/l", "g/l", "mg/l", "ug/l", "ng/ml", "u/l", "mu/l", "%", "fl", "pg",
  "x109/l", "x1012/l", "l/l", "ml/min/1.73m2", "mg/mmol", "mmol/mol", "ratio", "s", "mm/h", "g/dl", "mg/dl", "kg/m2"];

// ---------- dates ----------

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };

function isoDate(d: number, m: number, y: number): string | null {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCDate() !== d) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Dates in a string (Australian order: day first). */
export function datesIn(s: string): string[] {
  const out: string[] = [];
  // the same "/" or "-" both times, so a range like "11.5-16.5" isn't read as a date
  for (const m of s.matchAll(/(?<![\d.])(\d{1,2})([/-])(\d{1,2})\2(\d{2,4})(?![\d.])/g)) {
    const v = isoDate(+m[1], +m[3], +m[4]);
    if (v) out.push(v);
  }
  for (const m of s.matchAll(/\b(\d{1,2})[\s-]([A-Za-z]{3,4})[a-z]*[\s-](\d{2,4})\b/g)) {
    const mo = MONTHS[m[2].toLowerCase()];
    const v = mo ? isoDate(+m[1], mo, +m[3]) : null;
    if (v) out.push(v);
  }
  for (const m of s.matchAll(/\b(\d{4})-(\d{2})-(\d{2})\b/g)) {
    const v = isoDate(+m[3], +m[2], +m[1]);
    if (v) out.push(v);
  }
  return out;
}

const DATE_LABEL = /\b(date\s+collected|collected|collection(\s+date)?|specimen\s+(collected|date)|date\s+of\s+(collection|sample)|sample\s+date)\b/i;
const OTHER_LABEL = /\b(reported|received|printed|requested|registered|dob|date\s+of\s+birth)\b/i;

/** The collection date: the dates right after a "collected" label (up to the next other label).
 *  More than one distinct date → ambiguous (e.g. a report with several collections side by side). */
export function findCollectionDate(lines: Line[]): { date: string | null; note: string | null } {
  const found = new Set<string>();
  for (const l of lines) {
    const m = DATE_LABEL.exec(l.text);
    if (!m) continue;
    let rest = l.text.slice(m.index + m[0].length);
    const stop = OTHER_LABEL.exec(rest);
    if (stop) rest = rest.slice(0, stop.index);
    for (const d of datesIn(rest)) found.add(d);
  }
  if (found.size === 1) return { date: [...found][0], note: null };
  if (found.size === 0) return { date: null, note: "no collection date found" };
  return { date: [...found].sort().at(-1) ?? null, note: `more than one collection date (${[...found].sort().join(", ")})` };
}

// ---------- one line ----------

const SKIP = /\b(collected|reported|received|requested|dob|date of birth|medicare|phone|fax|lab(oratory)? (no|number|ref)|page \d|ref(erence)? (range|interval)|units?\b.*\brange|patient|address|doctor|copy to|provider)\b/i;
const NUM = /^(<=|>=|<|>|≤|≥)?\s*(\d+(?:\.\d+)?)$/;
const FLAG = /^(HH|LL|H|L|\*)$/;

type Parsed = {
  valueText: string; value: number | null; comparator: string | null; flag: ReadValue["lab_flag"];
  unit: string | null; rangeText: string | null; low: number | null; high: number | null; extraNumbers: number;
};

function parseRange(s: string): { low: number | null; high: number | null; text: string } | null {
  const t = s.trim().replace(/^[([]|[)\]]$/g, "").trim();
  let m = t.match(/^(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)$/);
  if (m) return { low: +m[1], high: +m[2], text: s.trim() };
  m = t.match(/^(<=|<|≤)\s*(\d+(?:\.\d+)?)$/);
  if (m) return { low: null, high: +m[2], text: s.trim() };
  m = t.match(/^(>=|>|≥)\s*(\d+(?:\.\d+)?)$/);
  if (m) return { low: +m[2], high: null, text: s.trim() };
  return null;
}

/** Splits the part of a line after the test name into value, flag, unit and range. */
export function parseResultTail(tail: string): Parsed | null {
  const tokens = tail.replace(/([([])\s+/g, "$1").replace(/\s+([)\]])/g, "$1").replace(/(\d)\s*(-|–)\s*(\d)/g, "$1-$3")
    .split(/\s+/).filter(Boolean);
  let i = 0;
  const p: Parsed = { valueText: "", value: null, comparator: null, flag: null, unit: null, rangeText: null, low: null, high: null, extraNumbers: 0 };
  // value (a comparator may be a separate token: "< 5")
  if (/^(<=|>=|<|>|≤|≥)$/.test(tokens[0] ?? "") && NUM.test(tokens[1] ?? "")) { tokens.splice(0, 2, tokens[0] + tokens[1]); }
  let first = tokens[i] ?? "";
  let flagStuck: string | null = null;
  const stuck = first.match(/^((?:<=|>=|<|>|≤|≥)?\d+(?:\.\d+)?)(HH|LL|H|L|\*)$/);
  if (stuck) { first = stuck[1]; flagStuck = stuck[2]; }
  const m = first.match(NUM);
  if (!m) return null;
  p.valueText = first;
  p.comparator = m[1] ?? null;
  p.value = +m[2];
  i++;
  if (flagStuck) p.flag = flagStuck as Parsed["flag"];
  for (; i < tokens.length; i++) {
    const t = tokens[i];
    if (!p.flag && FLAG.test(t)) { p.flag = t as Parsed["flag"]; continue; }
    if (!p.rangeText) {
      const r = parseRange(t);
      if (r && (/^[([]/.test(t) || /\d(-|–)\d/.test(t) || /^(<=|>=|<|>|≤|≥)/.test(t))) {
        Object.assign(p, { rangeText: r.text, low: r.low, high: r.high });
        continue;
      }
      if (/^[([]?\d/.test(t) && /^to$/i.test(tokens[i + 1] ?? "")) {
        const r3 = parseRange(tokens.slice(i, i + 3).join(" "));
        if (r3) { Object.assign(p, { rangeText: r3.text, low: r3.low, high: r3.high }); i += 2; continue; }
      }
    }
    if (!p.unit && !NUM.test(t) && /[a-zA-Zµμ%/]/.test(t)) { p.unit = t; continue; }
    if (NUM.test(t) && !p.rangeText) p.extraNumbers++;
  }
  return p;
}

type NameIndex = { key: string; marker: ReaderMarker }[];

function nameIndex(markers: ReaderMarker[]): NameIndex {
  const idx: NameIndex = [];
  for (const mk of markers) {
    for (const n of new Set([mk.name, ...(mk.names ?? [])])) {
      const key = normName(n);
      if (key) idx.push({ key, marker: mk });
    }
  }
  return idx.sort((a, b) => b.key.length - a.key.length);   // longest first: "free t4" before "t4"
}

/** The marker named at the start of the line, and the rest of the line. */
function matchName(line: Line, idx: NameIndex): { marker: ReaderMarker | null; printed: string; tail: string } | null {
  const text = line.text;
  const n = normName(text);
  for (const { key, marker } of idx) {
    if (n === key || n.startsWith(key + " ")) {
      // walk the printed text to the same number of normalised words
      const words = key.split(" ").length;
      const parts = text.split(/\s+/);
      let taken = 0, cut = 0;
      for (let j = 0; j < parts.length && taken < words; j++) {
        const w = normName(parts[j]);
        if (w) taken += w.split(" ").length;
        cut = j + 1;
      }
      return { marker, printed: parts.slice(0, cut).join(" "), tail: parts.slice(cut).join(" ") };
    }
  }
  // an unknown test: words up to the first number
  const m = text.match(/^([A-Za-z][A-Za-z0-9 ,.'()/+-]*?)\s+((?:<=|>=|<|>|≤|≥)?\s*\d[\s\S]*)$/);
  if (!m) return null;
  return { marker: null, printed: m[1].trim(), tail: m[2] };
}

function unitFactor(marker: ReaderMarker, printed: string | null): number | null {
  if (!printed) return null;
  const u = normUnit(printed);
  if (marker.unit && normUnit(marker.unit) === u) return 1;
  for (const c of marker.units ?? []) if (normUnit(c.unit) === u) return c.factor;
  return null;
}

/** Reads every result line. `method` is "ocr" when the text came from a photo or scan. */
export function readReport(lines: Line[], markers: ReaderMarker[], method: "text" | "ocr" = "text"): ReadResult {
  const idx = nameIndex(markers);
  const { date, note } = findCollectionDate(lines);
  const values: ReadValue[] = [];
  let unmatched = 0;
  for (const line of lines) {
    if (SKIP.test(line.text) || datesIn(line.text).length) continue;
    const hit = matchName(line, idx);
    if (!hit) continue;
    const p = parseResultTail(hit.tail);
    if (!p) continue;
    const looksLikeResult = !!p.rangeText || (!!p.unit && KNOWN_UNITS.includes(normUnit(p.unit)));
    if (!hit.marker && !looksLikeResult) continue;
    const reasons: string[] = [];
    if (method !== "text") reasons.push("read from a photo or scan");
    if (!hit.marker) { reasons.push("test name not on the marker list"); unmatched++; }
    const factor = hit.marker ? unitFactor(hit.marker, p.unit) : null;
    if (hit.marker) {
      if (!p.unit) reasons.push("no unit printed");
      else if (factor == null) reasons.push(`unit ${p.unit} isn't the marker's unit (${hit.marker.unit ?? "none set"})`);
    }
    if (p.comparator) reasons.push(`the result is a limit (${p.valueText}), not an exact number`);
    if (p.extraNumbers > 0) reasons.push("more than one number on the line (several dates side by side?)");
    const value = p.value;
    if (hit.marker && value != null) {
      const lo = hit.marker.plausibleLow, hi = hit.marker.plausibleHigh;
      const inMarkerUnit = value * (factor ?? 1);   // limits are in the marker's own unit
      if (lo == null && hi == null) reasons.push("no plausibility limits set for this marker yet");
      else if (factor == null) reasons.push("can't check plausibility without a known unit");
      else if ((lo != null && inMarkerUnit < lo) || (hi != null && inMarkerUnit > hi)) reasons.push("outside the plausibility limits");
    }
    if (!p.rangeText) reasons.push("no reference range printed");
    else if (value != null) {
      const above = p.high != null && value > p.high, below = p.low != null && value < p.low;
      const flagHigh = p.flag === "H" || p.flag === "HH", flagLow = p.flag === "L" || p.flag === "LL";
      if (above !== flagHigh || below !== flagLow || (p.flag === "*" && !above && !below)) reasons.push("the lab's flag and range don't agree with the number");
    }
    if (!date) reasons.push(note ?? "no collection date found");
    else if (note) reasons.push(note);
    values.push({
      marker_code: hit.marker?.code ?? null,
      name_as_printed: hit.printed.slice(0, 200),
      value,
      value_text: p.valueText.slice(0, 60),
      unit_as_printed: p.unit?.slice(0, 40) ?? null,
      value_std: value != null && factor != null && !p.comparator ? Math.round(value * factor * 1e6) / 1e6 : null,
      lab_low: p.low,
      lab_high: p.high,
      lab_range_text: p.rangeText?.slice(0, 80) ?? null,
      lab_flag: p.flag,
      measured_on: date,
      page: line.page,
      line_text: line.text.slice(0, 500),
      method,
      certainty: reasons.length ? "check" : "sure",
      check_reasons: reasons,
    });
  }
  const pages = new Set(lines.map((l) => l.page)).size;
  const sure = values.filter((v) => v.certainty === "sure").length;
  return { reader_version: READER_VERSION, method, measured_on: date, date_note: note, values, pages, sure, please_check: values.length - sure, unmatched };
}
