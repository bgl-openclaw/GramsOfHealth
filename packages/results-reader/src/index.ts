/**
 * Results reader: finds blood test values in the text of a pathology report.
 * Runs in the browser; nothing leaves the device. The app supplies the PDF's text items (pdf.js getTextContent)
 * and the marker list (clinical_markers); this returns one row per value, ready for client_result_values.
 *
 * Layouts handled:
 *   • "Ferritin  45  ug/L  (30-500)"            value first, then unit and range (flag anywhere)
 *   • "Ferritin(30-400) ug/L  60  92"           range and unit first, then one value per collection date
 *     (cumulative reports: the "Date Collected" row above gives each column's date; the column for this report's
 *      collection — matched by request number when the report prints one — is the value read)
 *
 * A value is "sure" only when every rule holds (docs/RESULTS-READER-PLAN.md):
 *   1 read from the PDF's own text (photos/scans: always "check")
 *   2 the test name matches a marker name or a name labs print for it
 *   3 the unit is the marker's unit, or one with a known exact conversion
 *   4 the number is clean (no limit sign) and is the only candidate, or its date column is known
 *   5 it is inside the marker's plausibility limits
 *   6 if the lab printed a range or flag, they agree with the number
 *   7 one collection date was found on the report
 * Anything else is "check", with the reasons listed.
 */

export const READER_VERSION = "0.2.0";

export type TextItem = { str: string; x: number; y: number; page: number; height?: number };
export type Line = { page: number; y: number; text: string; cells: { text: string; x: number }[] };

export type ReaderMarker = {
  code: string;
  name: string;
  unit: string | null;
  /** Names and abbreviations labs print (the marker's own name is always included). */
  names?: string[];
  /** Printed units with the conversion to the marker's unit: value × factor + offset. "" = no unit printed is fine. */
  units?: { unit: string; factor: number; offset?: number }[];
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
  return s.toLowerCase().replace(/[µμ]/g, "u").replace(/\s+/g, "").replace(/\^|\*/g, "").replace(/²/g, "2").replace(/iu\//g, "u/");
}

/** Tidies a printed line so names, ranges, limits and units come apart cleanly. */
export function cleanLine(s: string): string {
  return s
    .replace(/([A-Za-z.'])\(/g, "$1 (")              // "Ferritin(30-400)" → "Ferritin (30-400)"
    .replace(/([([])\s+/g, "$1").replace(/\s+([)\]])/g, "$1")
    .replace(/(<=|>=|<|>|≤|≥)\s+(?=\d)/g, "$1")      // "< 3.0" → "<3.0", "(< 31)" → "(<31)"
    .replace(/(\d)\s*(?:-|–)\s*(\d)/g, "$1-$2")      // "30 - 500" → "30-500"
    .replace(/(\d)\s+to\s+(\d)/gi, "$1-$2")          // "3.0 to 5.5" → "3.0-5.5"
    .replace(/(\S)\s+\/(?=[A-Za-z])/g, "$1/")        // "x10^12 /L" → "x10^12/L"
    .replace(/\s+/g, " ").trim();
}

// ---------- dates ----------

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };

function isoDate(d: number, m: number, y: number): string | null {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCDate() !== d) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Dates in a string, in the order they appear (Australian order: day first). */
export function datesIn(s: string): string[] {
  const found: { at: number; iso: string }[] = [];
  // the same "/" or "-" both times, so a range like "11.5-16.5" isn't read as a date
  for (const m of s.matchAll(/(?<![\d.])(\d{1,2})([/-])(\d{1,2})\2(\d{2,4})(?![\d.])/g)) {
    const v = isoDate(+m[1], +m[3], +m[4]);
    if (v) found.push({ at: m.index ?? 0, iso: v });
  }
  for (const m of s.matchAll(/\b(\d{1,2})[\s-]([A-Za-z]{3,4})[a-z]*[\s-](\d{2,4})\b/g)) {
    const mo = MONTHS[m[2].toLowerCase()];
    const v = mo ? isoDate(+m[1], mo, +m[3]) : null;
    if (v) found.push({ at: m.index ?? 0, iso: v });
  }
  for (const m of s.matchAll(/\b(\d{4})-(\d{2})-(\d{2})\b/g)) {
    const v = isoDate(+m[3], +m[2], +m[1]);
    if (v) found.push({ at: m.index ?? 0, iso: v });
  }
  return found.sort((a, b) => a.at - b.at).map((f) => f.iso);
}

const DATE_LABEL = /\b(date\s+collected|collected|collection(\s+date)?|specimen\s+(collected|date)|date\s+of\s+(collection|sample)|sample\s+date)\b/i;
const OTHER_LABEL = /\b(reported|received|printed|requested|registered|dob|date\s+of\s+birth)\b/i;
const COLUMN_HEADER = /^(date\s+collected|collected|collection\s+date)\b(?!\s*:)/i;

/** A cumulative report's column row: "Date Collected  4 Jun 25  16 Oct 26" (no colon, no other label, 2+ dates). */
function isColumnHeader(text: string): boolean {
  return COLUMN_HEADER.test(text) && !OTHER_LABEL.test(text) && datesIn(text).length >= 2;
}

/** The report's collection date: the date right after a "Collected" label (up to the next other label).
 *  Cumulative column rows ("Date Collected  4 Jun 25  16 Oct 26") are not counted here.
 *  More than one distinct date → ambiguous. */
export function findCollectionDate(lines: Line[]): { date: string | null; note: string | null } {
  const found = new Set<string>();
  for (const l of lines) {
    if (isColumnHeader(l.text)) continue;
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

const SKIP = /\b(reported|received|requested|dob|date of birth|medicare|phone|fax|lab(oratory)? (no|number|ref)|page \d|ref(erence)? (range|interval)|units?\b.*\brange|patient|address|doctor|copy to|provider|request number|time collected|specimen type)\b/i;
const NUM = /^(<=|>=|<|>|≤|≥)?(\d+(?:\.\d+)?)$/;
const KNOWN_UNITS = ["mmol/l", "umol/l", "nmol/l", "pmol/l", "g/l", "mg/l", "ug/l", "ng/ml", "u/l", "mu/l", "%", "fl", "pg",
  "x109/l", "x1012/l", "l/l", "mg/mmol", "mmol/mol", "ratio", "s", "mm/h", "g/dl", "mg/dl", "kg/m2"];
function isUnitToken(t: string): boolean {
  return /[/%\d^]/.test(t) || KNOWN_UNITS.includes(normUnit(t));
}
const FLAG = /^(HH|LL|H|L|\*)$/;

type Range = { low: number | null; high: number | null; text: string };
type Parsed = {
  values: { text: string; value: number; comparator: string | null }[];
  flag: ReadValue["lab_flag"];
  unit: string | null;
  range: Range | null;
};

function parseRange(s: string): Range | null {
  const t = s.trim().replace(/^[([]|[)\]]$/g, "").trim();
  let m = t.match(/^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$/);
  if (m) return { low: +m[1], high: +m[2], text: s.trim() };
  m = t.match(/^(<=|<|≤)(\d+(?:\.\d+)?)$/);
  if (m) return { low: null, high: +m[2], text: s.trim() };
  m = t.match(/^(>=|>|≥)(\d+(?:\.\d+)?)$/);
  if (m) return { low: +m[2], high: null, text: s.trim() };
  return null;
}

/** Splits the part of a line after the test name into values, flag, unit and range, in any order. */
export function parseResultTail(tail: string): Parsed | null {
  const tokens = cleanLine(tail).split(" ").filter(Boolean);
  const p: Parsed = { values: [], flag: null, unit: null, range: null };
  let words = 0;
  for (const raw of tokens) {
    let t = raw;
    const stuckFlag = t.match(/^((?:<=|>=|<|>|≤|≥)?\d+(?:\.\d+)?)(HH|LL|H|L|\*)$/);
    if (stuckFlag) { t = stuckFlag[1]; if (!p.flag) p.flag = stuckFlag[2] as Parsed["flag"]; }
    const stuckPct = t.match(/^(\d+(?:\.\d+)?)%$/);
    if (stuckPct) { t = stuckPct[1]; if (!p.unit) p.unit = "%"; }
    if (!p.flag && FLAG.test(t)) { p.flag = t as Parsed["flag"]; continue; }
    if (/^[([]/.test(t) || /\d-\d/.test(t)) {
      const r = parseRange(t);
      if (r && !p.range) { p.range = r; continue; }
      if (r) continue;
    }
    const m = t.match(NUM);
    if (m) { p.values.push({ text: t, value: +m[2], comparator: m[1] ?? null }); continue; }
    if (!p.unit && /[a-zA-Zµμ%/]/.test(t)) { p.unit = t; continue; }
    if (/[A-Za-z]/.test(t)) words++;
  }
  if (words >= 2) return null;                       // a sentence, not a result line
  // "2 mg/L <5": a trailing limit after a plain value is the range, not a second value
  if (!p.range && p.values.length >= 2) {
    const last = p.values[p.values.length - 1];
    if (last.comparator && p.values.slice(0, -1).every((v) => !v.comparator)) {
      p.range = parseRange(last.text);
      p.values.pop();
    }
  }
  return p.values.length ? p : null;
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
function matchName(text: string, idx: NameIndex): { marker: ReaderMarker | null; printed: string; tail: string } | null {
  const n = normName(text);
  for (const { key, marker } of idx) {
    if (n === key || n.startsWith(key + " ")) {
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
  // an unknown test: words up to the first range or number
  const m = text.match(/^([A-Za-z][A-Za-z0-9 ,.'/+-]*?)\s+([([]|(?:<=|>=|<|>|≤|≥)?\d)([\s\S]*)$/);
  if (!m) return null;
  return { marker: null, printed: m[1].trim(), tail: m[2] + m[3] };
}

function conversion(marker: ReaderMarker, printed: string | null): { factor: number; offset: number } | null {
  const own = marker.unit ? [marker.unit, marker.unit.split(" (")[0]] : [];
  const u = normUnit(printed ?? "");
  if (printed && own.some((o) => normUnit(o) === u)) return { factor: 1, offset: 0 };
  for (const c of marker.units ?? []) if (normUnit(c.unit) === u) return { factor: c.factor, offset: c.offset ?? 0 };
  return null;
}

type Columns = { dates: string[]; ids: string[] | null };

/** Reads every result line. `method` is "ocr" when the text came from a photo or scan. */
export function readReport(lines: Line[], markers: ReaderMarker[], method: "text" | "ocr" = "text"): ReadResult {
  const idx = nameIndex(markers);
  const { date, note } = findCollectionDate(lines);
  const values: (ReadValue & { native: boolean })[] = [];
  let cols: Columns | null = null;
  let pendingIds: string[] | null = null;
  let requestId: string | null = null;
  for (const line of lines) {
    const text = cleanLine(line.text);
    // section boundaries and cumulative headers
    if (/^name of test\b/i.test(text)) { cols = null; pendingIds = null; continue; }
    const ref = text.match(/\blab(?:oratory)?\s*ref(?:erence)?\s*:?\s*\d+-(\d{5,})-/i);
    if (ref) { requestId = ref[1]; cols = null; pendingIds = null; continue; }
    if (/^request\s+number\b/i.test(text)) { pendingIds = text.match(/\b\d{5,}\b/g); continue; }
    if (isColumnHeader(text)) {
      const dates = datesIn(text);
      cols = { dates, ids: pendingIds && pendingIds.length === dates.length ? pendingIds : null };
      continue;
    }
    if (SKIP.test(text) || DATE_LABEL.test(text) || datesIn(text).length) continue;
    const hit = matchName(text, idx);
    if (!hit) continue;
    const tail = hit.tail.split(" ").filter(Boolean);
    while (tail.length && /^[A-Za-z][A-Za-z'.-]*$/.test(tail[0]) && !FLAG.test(tail[0]) && !isUnitToken(tail[0])
           && !(hit.marker && conversion(hit.marker, tail[0]))) {
      hit.printed += " " + tail.shift();
    }
    const p = parseResultTail(tail.join(" "));
    if (!p) continue;
    if (!hit.marker && !p.range) continue;            // unknown tests count only when a range is printed
    const reasons: string[] = [];
    if (method !== "text") reasons.push("read from a photo or scan");
    if (!hit.marker) reasons.push("test name not on the marker list");

    // which value, and its date
    let pick = p.values[0];
    let measured: string | null = date;
    if (cols && cols.dates.length >= 2) {
      if (p.values.length === cols.dates.length) {
        let i = cols.ids && requestId ? cols.ids.indexOf(requestId) : -1;
        if (i < 0) {
          const same = cols.dates.map((d, j) => (d === date ? j : -1)).filter((j) => j >= 0);
          if (same.length === 1) i = same[0];
          else if (same.length > 1) { i = same[same.length - 1]; reasons.push("two collections on the report's date; took the last column"); }
          else { i = cols.dates.length - 1; reasons.push("this report's date isn't among the columns; took the last column"); }
        }
        pick = p.values[i];
        measured = cols.dates[i];
      } else {
        pick = p.values[p.values.length - 1];
        reasons.push("couldn't line the values up with their dates; took the last one");
      }
    } else if (p.values.length > 1) {
      reasons.push("more than one number on the line (several dates side by side?)");
    }

    const conv = hit.marker ? conversion(hit.marker, p.unit) ?? (!p.unit ? conversion(hit.marker, "") : null) : null;
    if (hit.marker && !conv) {
      if (!p.unit) reasons.push("no unit printed");
      else reasons.push(`unit ${p.unit} isn't the marker's unit (${hit.marker.unit ?? "none set"})`);
    }
    if (pick.comparator) reasons.push(`the result is a limit (${pick.text}), not an exact number`);
    const value = pick.value;
    const inMarkerUnit = conv ? Math.round((value * conv.factor + conv.offset) * 1e6) / 1e6 : null;
    if (hit.marker) {
      const lo = hit.marker.plausibleLow, hi = hit.marker.plausibleHigh;
      if (lo == null && hi == null) reasons.push("no plausibility limits set for this marker yet");
      else if (inMarkerUnit == null) reasons.push("can't check plausibility without a known unit");
      else if ((lo != null && inMarkerUnit < lo) || (hi != null && inMarkerUnit > hi)) reasons.push("outside the plausibility limits");
    }
    if (p.range && !pick.comparator) {
      const above = p.range.high != null && value > p.range.high, below = p.range.low != null && value < p.range.low;
      const flagHigh = p.flag === "H" || p.flag === "HH", flagLow = p.flag === "L" || p.flag === "LL";
      // a flag must match the side the value is on; no flag is fine (cumulative reports rarely print one per column)
      if ((flagHigh && !above) || (flagLow && !below) || (p.flag === "*" && !above && !below)) {
        reasons.push("the lab's flag and range don't agree with the number");
      }
    }
    if (!date) reasons.push(note ?? "no collection date found");
    else if (note) reasons.push(note);
    values.push({
      marker_code: hit.marker?.code ?? null,
      name_as_printed: hit.printed.slice(0, 200),
      value,
      value_text: pick.text.slice(0, 60),
      unit_as_printed: p.unit?.slice(0, 40) ?? null,
      value_std: pick.comparator ? null : inMarkerUnit,
      lab_low: p.range?.low ?? null,
      lab_high: p.range?.high ?? null,
      lab_range_text: p.range?.text.slice(0, 80) ?? null,
      lab_flag: p.flag,
      measured_on: measured,
      page: line.page,
      line_text: line.text.slice(0, 500),
      method,
      certainty: reasons.length ? "check" : "sure",
      check_reasons: reasons,
      native: !!conv && conv.factor === 1 && conv.offset === 0 && !!p.unit,
    });
  }
  // The same test printed twice for one date (e.g. HbA1c in % and in mmol/mol): keep the one in the marker's own unit.
  const kept = values.filter((v) => v.native || !v.marker_code
    || !values.some((o) => o !== v && o.native && o.marker_code === v.marker_code && o.measured_on === v.measured_on));
  const out: ReadValue[] = kept.map(({ native: _n, ...v }) => v);
  const pages = new Set(lines.map((l) => l.page)).size;
  const sure = out.filter((v) => v.certainty === "sure").length;
  return {
    reader_version: READER_VERSION, method, measured_on: date, date_note: note, values: out, pages, sure,
    please_check: out.length - sure, unmatched: out.filter((v) => !v.marker_code).length,
  };
}
