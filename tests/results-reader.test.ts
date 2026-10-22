import { describe, expect, it } from "vitest";
import {
  findCollectionDate, itemsFromPdfJs, linesFromText, parseResultTail, readReport, toLines, type ReaderMarker,
} from "../packages/results-reader/src";

// Made-up markers and a made-up report in a common Australian layout (no real patient data).
const markers: ReaderMarker[] = [
  { code: "haemoglobin", name: "Haemoglobin", unit: "g/L", names: ["Hb", "Hemoglobin"], units: [{ unit: "g/dL", factor: 10 }], plausibleLow: 30, plausibleHigh: 250 },
  { code: "ferritin", name: "Ferritin", unit: "µg/L", names: ["FERR", "Serum ferritin"], plausibleLow: 1, plausibleHigh: 10000 },
  { code: "hba1c", name: "HbA1c", unit: "mmol/mol", plausibleLow: 15, plausibleHigh: 200 },
  { code: "free_t4", name: "Free T4", unit: "pmol/L", names: ["FT4"], plausibleLow: 1, plausibleHigh: 100 },
  { code: "tsh", name: "TSH", unit: "mU/L", units: [{ unit: "mIU/L", factor: 1 }], plausibleLow: 0.001, plausibleHigh: 500 },
  { code: "vitamin_d", name: "25-OH vitamin D", unit: "nmol/L", names: ["Vitamin D"] },
  { code: "egfr", name: "eGFR", unit: "mL/min/1.73m²", plausibleLow: 1, plausibleHigh: 200 },
];

const REPORT = [
  "Patient: ZZ Test  DOB: 01/01/1980",
  "Collected: 12/10/2026 08:30  Reported: 13/10/2026",
  "Test  Result  Units  Reference Range",
  "Haemoglobin  128  g/L  (115-165)",
  "Ferritin  18  L  ug/L  (30-500)",
  "HbA1c  41  mmol/mol  (<48)",
  "Free T4  15.2  pmol/L  (10-20)",
  "TSH  2.10  mIU/L  0.50 - 4.00",
  "Vitamin D  62  nmol/L  (>50)",
  "eGFR  >90  mL/min/1.73m2  (>60)",
  "Magnesium  0.85  mmol/L  (0.70-1.10)",
].join("\n");

const byCode = (r: ReturnType<typeof readReport>, code: string | null, name?: string) =>
  r.values.find((v) => v.marker_code === code && (name == null || v.name_as_printed === name))!;

describe("results reader", () => {
  const r = readReport(linesFromText(REPORT), markers);

  it("takes the date after 'Collected', not the reported date", () => {
    expect(r.measured_on).toBe("2026-10-12");
    expect(r.date_note).toBeNull();
  });

  it("reads clean values as sure, including an out-of-range one the lab flagged", () => {
    const hb = byCode(r, "haemoglobin");
    expect(hb).toMatchObject({ value: 128, unit_as_printed: "g/L", value_std: 128, lab_low: 115, lab_high: 165, certainty: "sure", check_reasons: [] });
    const fe = byCode(r, "ferritin");
    expect(fe).toMatchObject({ value: 18, lab_flag: "L", value_std: 18, lab_low: 30, lab_high: 500, certainty: "sure" });
    expect(byCode(r, "hba1c")).toMatchObject({ value: 41, lab_high: 48, lab_low: null, certainty: "sure" });
    expect(byCode(r, "free_t4")).toMatchObject({ name_as_printed: "Free T4", value: 15.2, certainty: "sure" });
    expect(byCode(r, "tsh")).toMatchObject({ value: 2.1, lab_low: 0.5, lab_high: 4, certainty: "sure" });
  });

  it("flags what it can't be sure of, with reasons", () => {
    expect(byCode(r, "vitamin_d").check_reasons).toContain("no plausibility limits set for this marker yet");
    const egfr = byCode(r, "egfr");
    expect(egfr.certainty).toBe("check");
    expect(egfr.check_reasons.join(" ")).toMatch(/limit \(>90\)/);
    expect(egfr.value_std).toBeNull();
    const mg = byCode(r, null, "Magnesium");
    expect(mg).toMatchObject({ value: 0.85, certainty: "check" });
    expect(mg.check_reasons).toContain("test name not on the marker list");
    expect(r.unmatched).toBe(1);
  });

  it("skips headers, patient details and date lines", () => {
    expect(r.values.map((v) => v.name_as_printed)).not.toContain("Patient:");
    expect(r.values).toHaveLength(8);
    expect(r.sure + r.please_check).toBe(8);
  });

  it("several results side by side are never sure", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nFerritin  18  25  31  ug/L  (30-500)"), markers);
    expect(c.values[0].check_reasons).toContain("more than one number on the line (several dates side by side?)");
  });

  it("several collection dates make every value 'check'", () => {
    const c = readReport(linesFromText("Collected  12/10/2026  03/04/2026\nFerritin  45  ug/L  (30-500)"), markers);
    expect(c.date_note).toMatch(/more than one collection date/);
    expect(c.values[0].certainty).toBe("check");
  });

  it("no date found → check", () => {
    const c = readReport(linesFromText("Ferritin  45  ug/L  (30-500)"), markers);
    expect(c.values[0].check_reasons).toContain("no collection date found");
  });

  it("a flag that disagrees with the range → check", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nFerritin  18  ug/L  (30-500)"), markers);
    expect(c.values[0].check_reasons).toContain("the lab's flag and range don't agree with the number");
  });

  it("converts a known unit and checks plausibility in the marker's unit", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nHb  12.8  g/dL  (11.5-16.5)"), markers);
    expect(c.values[0]).toMatchObject({ marker_code: "haemoglobin", value: 12.8, value_std: 128, certainty: "sure" });
  });

  it("an unknown unit is never sure", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nFerritin  18  ng/mL  L  (30-500)"), markers);
    expect(c.values[0].check_reasons.join(" ")).toMatch(/unit ng\/mL isn't the marker's unit/);
  });

  it("photos and scans are never sure", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nHaemoglobin  128  g/L  (115-165)"), markers, "ocr");
    expect(c.values[0].certainty).toBe("check");
    expect(c.values[0].check_reasons).toContain("read from a photo or scan");
  });

  it("matches the longest name first and doesn't read HbA1c as Hb", () => {
    const c = readReport(linesFromText("Collected: 12/10/2026\nHbA1c  41  mmol/mol  (<48)"), markers);
    expect(c.values[0].marker_code).toBe("hba1c");
  });

  it("parses common result layouts", () => {
    expect(parseResultTail("18L ug/L (30-500)")).toMatchObject({ value: 18, flag: "L", unit: "ug/L", low: 30, high: 500 });
    expect(parseResultTail("< 5 mg/L (<5)")).toMatchObject({ valueText: "<5", comparator: "<", high: 5 });
    expect(parseResultTail("4.1 mmol/L 3.0 to 5.5")).toMatchObject({ value: 4.1, low: 3, high: 5.5 });
  });

  it("finds a collection date written with a month name", () => {
    expect(findCollectionDate(linesFromText("Date collected: 3 Oct 2026  Printed 5/10/2026")).date).toBe("2026-10-03");
  });

  it("builds lines from pdf.js text items in reading order", () => {
    const items = itemsFromPdfJs(1, { items: [
      { str: "ug/L", transform: [1, 0, 0, 1, 300, 700], height: 10 },
      { str: "Ferritin", transform: [1, 0, 0, 1, 50, 700], height: 10 },
      { str: "45", transform: [1, 0, 0, 1, 200, 701], height: 10 },
      { str: "Collected: 12/10/2026", transform: [1, 0, 0, 1, 50, 760], height: 10 },
      { str: "(30-500)", transform: [1, 0, 0, 1, 400, 700], height: 10 },
    ] });
    const lines = toLines(items);
    expect(lines.map((l) => l.text)).toEqual(["Collected: 12/10/2026", "Ferritin 45 ug/L (30-500)"]);
    expect(readReport(lines, markers).values[0]).toMatchObject({ marker_code: "ferritin", value: 45, certainty: "sure" });
  });
});
