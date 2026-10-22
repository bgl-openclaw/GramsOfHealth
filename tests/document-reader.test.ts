import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { classifyDocument, medicareValid, parseAddress, parseMedication, readLetter, splitMedications, type Fact } from "../packages/document-reader/src";

const read = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");
const pick = (facts: Fact[], section: string, field?: string) => facts.filter((f) => f.section === section && (field == null || f.field === field));

describe("document reader: sorting", () => {
  it("knows a GP letter, and that it also carries pathology", () => {
    expect(classifyDocument(read("gp-letter-example.txt"))).toMatchObject({ kind: "gp_letter", contains: ["pathology"] });
  });
  it("knows a specialist letter", () => {
    expect(classifyDocument(read("specialist-letter-example.txt")).kind).toBe("specialist_letter");
  });
  it("knows a transcript and a pathology report", () => {
    const t = Array.from({ length: 8 }, (_, i) => (i % 2 ? "Client: I mostly skip breakfast." : "Dietitian: What does a usual day look like?")).join("\n");
    expect(classifyDocument(t).kind).toBe("transcript");
    expect(classifyDocument(read("laverty-cumulative.txt")).kind).toBe("pathology");
  });
});

describe("document reader: GP letter", () => {
  const text = read("gp-letter-example.txt");
  const facts = readLetter(text, "gp_letter");

  it("every fact quotes the document exactly", () => {
    for (const f of facts) expect(text.includes(f.quote)).toBe(true);
  });

  it("reads the patient, flagging what it can't be sure of", () => {
    expect(pick(facts, "client", "full_name")[0]).toMatchObject({ value: { value: "T" }, certainty: "check" });   // only an initial
    expect(pick(facts, "client", "date_of_birth")).toMatchObject([{ value: { value: "1967-07-17" }, certainty: "sure" }]);
    expect(pick(facts, "client", "sex")[0]).toMatchObject({ value: { value: "female" } });
    expect(pick(facts, "client", "phone")).toMatchObject([{ value: { value: "0488 888 888" }, certainty: "sure" }]);   // not the practice's, not the dietitian's
    expect(pick(facts, "client", "address_line")[0].value).toEqual({ value: "55 Fake Ave" });
    expect(pick(facts, "client", "postcode")[0].value).toEqual({ value: "2000" });
    expect(pick(facts, "medicare")[0]).toMatchObject({ value: { number: "11111111" }, certainty: "check" });
  });

  it("reads the referral and the GP", () => {
    expect(pick(facts, "referral")[0]).toMatchObject({
      value: { pathway: "medicare_chronic", plan_name: "GPMP", referral_date: "2026-10-21", reason: "dyslipidaemia", referrer_name: "Dr Alex Example" },
      certainty: "sure" });
    expect(pick(facts, "care_team", "gp")[0]).toMatchObject({ value: { role: "gp", name: "Dr Alex Example", provider_number: "1234567A",
      practice: "Example Family Doctors", phone: "02 9000 0000", fax: "9000 0001", email: "frontdesk@example.com",
      address: "75 Example Avenue, Exampletown NSW 2000" }, certainty: "sure" });
  });

  it("reads all ten medications, split out of run-on lines", () => {
    const meds = pick(facts, "medication").map((f) => f.value);
    expect(meds).toHaveLength(10);
    expect(meds).toContainEqual({ name: "Actemra", strength: "162mg/0.9mL", form: "Prefilled syringe", dose: "1 Syringe", frequency: "Once a week" });
    expect(meds).toContainEqual({ name: "Doxycycline", strength: "100mg", form: "Tablet", dose: "1 Tablet", frequency: "Twice a day for 7 days" });
    expect(meds).toContainEqual({ name: "Otodex", strength: "0.5mg;5mg;0.05mg/mL", form: "Ear Drops", dose: "4 drops", frequency: "Before bed" });
    expect(meds).toContainEqual({ name: "Panafcort", strength: "1mg", form: "Tablet", dose: "7mg", frequency: "Daily As directed" });
    expect(meds).toContainEqual({ name: "Havrix 1440", strength: "1,440 Elisa units", form: "Syringe", dose: "1 Syringe", frequency: "Stat" });
    expect(pick(facts, "medication").every((f) => f.certainty === "sure")).toBe(true);
  });

  it("reads allergies and the history with dates", () => {
    expect(pick(facts, "allergy").map((f) => f.value)).toEqual([{ kind: "nil_known" }]);
    const conds = pick(facts, "condition").map((f) => f.value);
    expect(conds).toHaveLength(6);
    expect(conds).toContainEqual({ condition: "Interstitial lung disease", noted_on: "2024-12-16" });
    expect(conds).toContainEqual({ condition: "Osteoporosis", noted_on: null });
  });
});

describe("document reader: specialist letter", () => {
  const text = read("specialist-letter-example.txt");
  const facts = readLetter(text, "specialist_letter");
  it("quotes the document exactly", () => { for (const f of facts) expect(text.includes(f.quote)).toBe(true); });
  it("reads the specialist, the patient, diagnoses, medications, allergy, measurements and plan", () => {
    expect(pick(facts, "care_team", "specialist")[0]).toMatchObject({ value: { name: "Dr Jane Citizen", specialty: "Endocrinologist", provider_number: "2345678B", phone: "02 9111 2222" } });
    expect(pick(facts, "client", "full_name")[0]).toMatchObject({ value: { value: "Sam Sample" }, certainty: "sure" });
    expect(pick(facts, "client", "date_of_birth")[0].value).toEqual({ value: "1980-03-02" });
    expect(pick(facts, "condition").map((f) => f.value.condition)).toEqual(["Type 2 diabetes mellitus", "Fatty liver disease"]);
    expect(pick(facts, "medication")[0].value).toMatchObject({ name: "Metformin XR", strength: "1000mg", form: "Tablet", dose: "2 Tablets", frequency: "with dinner" });
    expect(pick(facts, "allergy")[0].value).toEqual({ kind: "allergy", substance: "Penicillin", reaction: "rash" });
    expect(pick(facts, "measurement", "weight_kg")[0].value).toEqual({ value: 96.4, measured_on: "2026-10-14" });
    expect(pick(facts, "client", "height_cm")[0].value).toEqual({ value: 178 });
    expect(pick(facts, "note").every((f) => f.certainty === "check")).toBe(true);
    expect(pick(facts, "referral")).toHaveLength(0);
  });
});

describe("document reader: parts", () => {
  it("Medicare check digit", () => {
    expect(medicareValid("2123456701")).toBe(true);
    expect(medicareValid("2123456711")).toBe(false);
    expect(medicareValid("11111111")).toBe(false);
  });
  it("addresses", () => {
    expect(parseAddress("55 Fake Ave, EXAMPLETOWN. 2000")).toEqual({ address_line: "55 Fake Ave", suburb: "EXAMPLETOWN", state: null, postcode: "2000" });
    expect(parseAddress("1 Example St, Exampletown NSW 2000")).toMatchObject({ state: "NSW", postcode: "2000" });
    expect(parseAddress("Thank you for seeing")).toBeNull();
  });
  it("medication lines", () => {
    expect(splitMedications("A 1mg Tablet Daily. Bee 2mg Tablet Daily.")).toEqual(["A 1mg Tablet Daily", "Bee 2mg Tablet Daily."]);
    expect(parseMedication("Prolia 60mg/mL Injection 1 Injection Dec - June.")).toEqual({ name: "Prolia", strength: "60mg/mL", form: "Injection", dose: "1 Injection", frequency: "Dec - June" });
    expect(parseMedication("Vitamin D")).toBeNull();
  });
});
