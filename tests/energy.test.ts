import { describe, it, expect } from "vitest";
import {
  estimateEnergy,
  ageInYears,
  energyInputsFromRow,
  roundToNearest10,
  type EnergyInputs,
  type ActivityLevel,
} from "../packages/energy/src";

const ACT: Record<string, ActivityLevel> = {
  sedentary: { key: "sedentary", label: "Sedentary", factor: 1.2 },
  moderately_active: { key: "moderately_active", label: "Moderately active", factor: 1.55 },
  very_active: { key: "very_active", label: "Very active", factor: 1.725 },
};

// as_of fixed; DOB chosen so age is exactly the fixture age on as_of.
const AS_OF = "2026-10-15";
const base = (o: Partial<EnergyInputs>): EnergyInputs => ({
  as_of: AS_OF,
  weight_kg: null,
  weighed_on: AS_OF,
  height_cm: null,
  date_of_birth: null,
  sex: null,
  equation_sex: null,
  activity: null,
  protein_g_per_kg: null,
  ...o,
});

function ok(r: ReturnType<typeof estimateEnergy>) {
  if (!r.ok) throw new Error(`expected a result, got: ${r.message}`);
  return r;
}

describe("Mifflin-St Jeor — roadmap acceptance fixtures (exact)", () => {
  it("1. Male, 80 kg, 180 cm, 30 y → BMR 1780; moderately active → TDEE 2759", () => {
    const r = ok(estimateEnergy(base({ sex: "male", weight_kg: 80, height_cm: 180, date_of_birth: "1996-10-15", activity: ACT.moderately_active })));
    expect(r.age_years).toBe(30);
    expect(r.bmr).toBe(1780);
    expect(r.tdee).toBe(2759);
    expect(r.tdee_display).toBe(2760);
  });

  it("2. Female, 65 kg, 165 cm, 40 y → BMR 1320.25; sedentary → TDEE 1584.3", () => {
    const r = ok(estimateEnergy(base({ sex: "female", weight_kg: 65, height_cm: 165, date_of_birth: "1986-10-15", activity: ACT.sedentary })));
    expect(r.bmr).toBe(1320.25);
    expect(r.tdee).toBe(1584.3);
    expect(r.bmr_display).toBe(1320);
    expect(r.tdee_display).toBe(1580);
  });

  it("3. Female, 58 kg, 160 cm, 25 y, very active → BMR 1294; TDEE 2232.15", () => {
    const r = ok(estimateEnergy(base({ sex: "female", weight_kg: 58, height_cm: 160, date_of_birth: "2001-10-15", activity: ACT.very_active })));
    expect(r.bmr).toBe(1294);
    expect(r.tdee).toBe(2232.15);
  });

  it("4. Missing height, weight or date of birth → no result, message names the missing input", () => {
    const full = { sex: "female" as const, weight_kg: 60, height_cm: 165, date_of_birth: "1990-01-01" };
    const noHeight = estimateEnergy(base({ ...full, height_cm: null }));
    const noWeight = estimateEnergy(base({ ...full, weight_kg: null }));
    const noDob = estimateEnergy(base({ ...full, date_of_birth: null }));
    const none = estimateEnergy(base({ sex: "female" }));
    for (const [r, word] of [[noHeight, "height"], [noWeight, "weight"], [noDob, "date of birth"]] as const) {
      expect(r.ok).toBe(false);
      if (!r.ok) {
        expect(r.missing).toEqual([word]);
        expect(r.message).toContain(word);
      }
    }
    expect(none.ok).toBe(false);
    if (!none.ok) expect(none.missing).toEqual(["weight", "height", "date of birth"]);
  });

  it("5. Protein 1.8 g/kg at 70 kg → 126 g", () => {
    const r = ok(estimateEnergy(base({ sex: "male", weight_kg: 70, height_cm: 175, date_of_birth: "1990-01-01", protein_g_per_kg: 1.8 })));
    expect(r.protein_g).toBe(126);
  });
});

describe("rules", () => {
  it("age is completed years at the calculation date (birthday eve / day)", () => {
    expect(ageInYears("1996-10-16", "2026-10-15")).toBe(29);
    expect(ageInYears("1996-10-15", "2026-10-15")).toBe(30);
  });

  it("29 Feb birthday is reached on 1 Mar in non-leap years (matches Postgres age())", () => {
    expect(ageInYears("2000-02-29", "2023-02-28")).toBe(22);
    expect(ageInYears("2000-02-29", "2023-03-01")).toBe(23);
    expect(ageInYears("2000-02-29", "2024-02-29")).toBe(24);
  });

  it("future date of birth → treated as missing, never a guessed age", () => {
    const r = estimateEnergy(base({ sex: "male", weight_kg: 80, height_cm: 180, date_of_birth: "2030-01-01" }));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.missing).toEqual(["date of birth"]);
  });

  it("sex other/unspecified needs the dietitian's constant choice, which is shown on the result", () => {
    const inputs = { weight_kg: 80, height_cm: 180, date_of_birth: "1996-10-15" };
    const unchosen = estimateEnergy(base({ ...inputs, sex: "unspecified" }));
    expect(unchosen.ok).toBe(false);
    if (!unchosen.ok) expect(unchosen.missing[0]).toMatch(/equation sex/);
    const chosen = ok(estimateEnergy(base({ ...inputs, sex: "other", equation_sex: "male" })));
    expect(chosen.bmr).toBe(1780);
    expect(chosen.sex_constant).toBe("male");
    expect(chosen.sex_constant_chosen).toBe(true);
    // equation_sex is ignored when recorded sex is male/female
    const ignored = ok(estimateEnergy(base({ ...inputs, sex: "male", equation_sex: "female" })));
    expect(ignored.sex_constant).toBe("male");
    expect(ignored.sex_constant_chosen).toBe(false);
  });

  it("no activity level → BMR only, TDEE null, with a prompt", () => {
    const r = ok(estimateEnergy(base({ sex: "male", weight_kg: 80, height_cm: 180, date_of_birth: "1996-10-15" })));
    expect(r.tdee).toBeNull();
    expect(r.tdee_display).toBeNull();
    expect(r.warnings.join(" ")).toMatch(/activity level/);
  });

  it("no protein g/kg → no protein suggestion (no default imposed)", () => {
    const r = ok(estimateEnergy(base({ sex: "male", weight_kg: 80, height_cm: 180, date_of_birth: "1996-10-15" })));
    expect(r.protein_g).toBeNull();
  });

  it("weight older than 90 days and under-18 clients raise warnings, not errors", () => {
    const stale = ok(estimateEnergy(base({ sex: "female", weight_kg: 60, height_cm: 165, date_of_birth: "1990-01-01", weighed_on: "2026-06-01" })));
    expect(stale.warnings.join(" ")).toMatch(/136 days old/);
    const teen = ok(estimateEnergy(base({ sex: "female", weight_kg: 50, height_cm: 160, date_of_birth: "2010-01-01" })));
    expect(teen.warnings.join(" ")).toMatch(/under 18/);
  });

  it("working shows every input with its date", () => {
    const r = ok(estimateEnergy(base({ sex: "male", weight_kg: 80, weighed_on: "2026-10-01", height_cm: 180, date_of_birth: "1996-10-15", activity: ACT.moderately_active, protein_g_per_kg: 2 })));
    expect(r.working).toEqual({
      as_of: AS_OF, weight_kg: 80, weighed_on: "2026-10-01", height_cm: 180, date_of_birth: "1996-10-15",
      age_years: 30, sex: "male", sex_constant: "male", activity: ACT.moderately_active, protein_g_per_kg: 2,
    });
  });

  it("display rounds to the nearest 10; calculation keeps the unrounded value", () => {
    expect(roundToNearest10(2759)).toBe(2760);
    expect(roundToNearest10(1584.3)).toBe(1580);
    expect(roundToNearest10(2235)).toBe(2240);
  });
});

describe("energyInputsFromRow (client_energy_inputs RPC adapter)", () => {
  it("maps the RPC row, including Postgres numerics delivered as strings", () => {
    const inputs = energyInputsFromRow({
      client_id: "c1", as_of: AS_OF, weight_kg: "80.0", weighed_on: "2026-10-01", height_cm: "180",
      date_of_birth: "1996-10-15", sex: "male", equation_sex: null,
      activity_key: "moderately_active", activity_label: "Moderately active", activity_factor: "1.55",
      protein_g_per_kg: null,
    });
    const r = ok(estimateEnergy(inputs));
    expect(r.bmr).toBe(1780);
    expect(r.tdee).toBe(2759);
  });

  it("no activity on the client → activity null", () => {
    const inputs = energyInputsFromRow({
      client_id: "c1", as_of: AS_OF, weight_kg: null, weighed_on: null, height_cm: null, date_of_birth: null,
      sex: "unspecified", equation_sex: null, activity_key: null, activity_label: null, activity_factor: null,
      protein_g_per_kg: null,
    });
    expect(inputs.activity).toBeNull();
    const r = estimateEnergy(inputs);
    expect(r.ok).toBe(false);
  });
});
