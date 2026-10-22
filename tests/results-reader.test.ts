import { readFileSync } from "node:fs";
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
    const c = readReport(linesFromText("Collected: 12/10/2026, 03/04/2026\nFerritin  45  ug/L  (30-500)"), markers);
    expect(c.date_note).toMatch(/more than one collection date/);
    expect(c.values[0].certainty).toBe("check");
  });

  it("no date found → check", () => {
    const c = readReport(linesFromText("Ferritin  45  ug/L  (30-500)"), markers);
    expect(c.values[0].check_reasons).toContain("no collection date found");
  });

  it("a flag that disagrees with the range → check (no flag at all is fine)", () => {
    const ok = readReport(linesFromText("Collected: 12/10/2026\nFerritin  18  ug/L  (30-500)"), markers);
    expect(ok.values[0].certainty).toBe("sure");
    const c = readReport(linesFromText("Collected: 12/10/2026\nFerritin  18  H  ug/L  (30-500)"), markers);
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
    expect(parseResultTail("18L ug/L (30-500)")).toMatchObject({ values: [{ value: 18 }], flag: "L", unit: "ug/L", range: { low: 30, high: 500 } });
    expect(parseResultTail("< 5 mg/L (<5)")).toMatchObject({ values: [{ text: "<5", comparator: "<" }], range: { high: 5 } });
    expect(parseResultTail("4.1 mmol/L 3.0 to 5.5")).toMatchObject({ values: [{ value: 4.1 }], range: { low: 3, high: 5.5 } });
    expect(parseResultTail("2 mg/L <5")).toMatchObject({ values: [{ value: 2 }], range: { high: 5 } });
    expect(parseResultTail("(3.9-5.2) mmol/L 5.9 6.7")).toMatchObject({ values: [{ value: 5.9 }, { value: 6.7 }], range: { low: 3.9, high: 5.2 }, unit: "mmol/L" });
    expect(parseResultTail("values between 60 and 89 mL/min should be interpreted")).toBeNull();
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

// Laverty's cumulative layout (anonymised fixture): name (range) unit, then one value per collection date.
describe("results reader: Laverty cumulative report", () => {
  const lim = { plausibleLow: 0.01, plausibleHigh: 100000 };
  const lv: ReaderMarker[] = [
    { code: "total_cholesterol", name: "Total cholesterol", unit: "mmol/L", names: ["Chol"], ...lim },
    { code: "ldl_c", name: "LDL cholesterol", unit: "mmol/L", names: ["LDL"], ...lim },
    { code: "hdl_c", name: "HDL cholesterol", unit: "mmol/L", names: ["HDL"], ...lim },
    { code: "vitamin_d", name: "25-OH vitamin D", unit: "nmol/L", names: ["Serum 25(OH) Vitamin D"], ...lim },
    { code: "hba1c", name: "HbA1c", unit: "mmol/mol (%)", names: ["HbA1c- IFCC", "HbA1c- NGSP"], ...lim },
    { code: "crp", name: "CRP", unit: "mg/L", ...lim },
    { code: "tsh", name: "TSH", unit: "mU/L", units: [{ unit: "mIU/L", factor: 1 }], ...lim },
    { code: "ferritin", name: "Ferritin", unit: "µg/L", ...lim },
    { code: "sodium", name: "Sodium", unit: "mmol/L", names: ["Na"], ...lim },
    { code: "egfr", name: "eGFR", unit: "mL/min/1.73m²", units: [{ unit: "mL/min/1.73sqM", factor: 1 }], ...lim },
    { code: "haematocrit", name: "Haematocrit", unit: "L/L", names: ["Hct"], units: [{ unit: "", factor: 1 }], ...lim },
  ];
  const r = readReport(linesFromText(readFileSync(new URL("./fixtures/laverty-cumulative.txt", import.meta.url), "utf8")), lv);
  const get = (code: string) => r.values.filter((v) => v.marker_code === code);

  it("reads this report's column, not the oldest one", () => {
    expect(r.measured_on).toBe("2026-10-16");
    expect(get("total_cholesterol")).toMatchObject([{ value: 6.7, measured_on: "2026-10-16", lab_low: 3.9, lab_high: 5.2, certainty: "sure" }]);
    expect(get("ldl_c")[0]).toMatchObject({ value: 4, certainty: "sure" });
    expect(get("tsh")[0]).toMatchObject({ value: 2, measured_on: "2026-10-16", certainty: "sure" });
    expect(get("ferritin")[0]).toMatchObject({ value: 92, name_as_printed: "Ferritin", lab_low: 30, lab_high: 400, certainty: "sure" });
  });

  it("two collections on the same day: the request number picks the column", () => {
    expect(get("sodium")[0]).toMatchObject({ value: 142, certainty: "sure", check_reasons: [] });
    expect(get("egfr")).toMatchObject([{ value: 88, certainty: "sure" }]);   // the eGFR sentence below the table is ignored
  });

  it("limits stay 'check'; a unitless test can be sure when the marker allows it", () => {
    expect(get("crp")[0]).toMatchObject({ value_text: "<3.0", certainty: "check" });
    expect(get("haematocrit")[0]).toMatchObject({ value: 0.47, certainty: "sure" });
  });

  it("HbA1c printed in % and mmol/mol: keeps the marker's own unit", () => {
    expect(get("hba1c")).toMatchObject([{ value: 32, unit_as_printed: "mmol/mol", name_as_printed: "HbA1c- IFCC" }]);
  });

  it("a value without a printed range can be sure (vitamin D)", () => {
    expect(get("vitamin_d")[0]).toMatchObject({ value: 54, certainty: "sure" });
  });

  it("ignores the lab's decision-limit and target text", () => {
    const names = r.values.map((v) => v.name_as_printed);
    for (const n of ["Sufficiency", "Mild deficiency", "Marked deficiency", "Toxicity", "Haemolysis", "Fasting status"]) expect(names).not.toContain(n);
    expect(r.values.every((v) => v.measured_on === "2026-10-16")).toBe(true);
  });

  it("tests not on the marker list come through as 'check' when the lab printed a range", () => {
    const unknown = r.values.filter((v) => !v.marker_code).map((v) => v.name_as_printed);
    expect(unknown).toEqual(expect.arrayContaining(["Trig", "Iron", "K", "Creat", "Alk Phos", "Hb", "Plat"]));
    expect(r.values.filter((v) => !v.marker_code).every((v) => v.certainty === "check")).toBe(true);
  });
});
