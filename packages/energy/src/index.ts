// @goh/energy — Mifflin-St Jeor energy estimate. A helper that PROPOSES;
// the dietitian's saved targets are always the numbers that count.
//
//   BMR (kcal/day) = 10 × weight_kg + 6.25 × height_cm − 5 × age_years + s
//   s = +5 (male), −161 (female)
//   TDEE = BMR × activity factor
//
// Pure: no I/O, no clock. The caller passes the calculation date (`as_of`).
// Lovable keeps a byte-identical copy at src/lib/energy.ts — change both together.

export type SexConstant = "male" | "female";
export type RecordedSex = "female" | "male" | "other" | "unspecified";

export const SEX_CONSTANT: Record<SexConstant, number> = { male: 5, female: -161 };

/** Warn when the most recent weight is older than this many days. */
export const STALE_WEIGHT_DAYS = 90;

export type ActivityLevel = { key: string; label: string; factor: number };

export type EnergyInputs = {
  /** ISO date (YYYY-MM-DD) the calculation is for. */
  as_of: string;
  weight_kg: number | null;
  /** ISO date of the weight entry used. */
  weighed_on: string | null;
  height_cm: number | null;
  /** ISO date of birth. */
  date_of_birth: string | null;
  sex: RecordedSex | null;
  /** Constant the dietitian chose when sex is other/unspecified. Ignored for male/female. */
  equation_sex: SexConstant | null;
  activity: ActivityLevel | null;
  /** Dietitian-entered g/kg. No default is ever imposed. */
  protein_g_per_kg: number | null;
};

export type EnergyResult =
  | {
      ok: true;
      bmr: number;
      /** null until an activity level is chosen. */
      tdee: number | null;
      /** Nearest 10 kcal, for display only. */
      bmr_display: number;
      tdee_display: number | null;
      age_years: number;
      sex_constant: SexConstant;
      /** true when the constant came from the dietitian's choice (sex other/unspecified). */
      sex_constant_chosen: boolean;
      factor: number | null;
      protein_g: number | null;
      /** Every input with its date, so the dietitian can see where the number came from. */
      working: {
        as_of: string;
        weight_kg: number;
        weighed_on: string | null;
        height_cm: number;
        date_of_birth: string;
        age_years: number;
        sex: RecordedSex | null;
        sex_constant: SexConstant;
        activity: ActivityLevel | null;
        protein_g_per_kg: number | null;
      };
      warnings: string[];
    }
  | { ok: false; missing: string[]; message: string };

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

function parseIsoDate(s: string): [number, number, number] | null {
  const m = ISO_DATE.exec(s.slice(0, 10));
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

/**
 * Completed years on `asOf`. A 29 Feb birthday counts as reached on 1 Mar in
 * non-leap years (matches Postgres age()). Null if either date is invalid or
 * the birth date is after `asOf`.
 */
export function ageInYears(dateOfBirth: string, asOf: string): number | null {
  const b = parseIsoDate(dateOfBirth);
  const a = parseIsoDate(asOf);
  if (!b || !a) return null;
  let age = a[0] - b[0];
  if (a[1] < b[1] || (a[1] === b[1] && a[2] < b[2])) age -= 1;
  return age < 0 ? null : age;
}

function daysBetween(from: string, to: string): number | null {
  const f = parseIsoDate(from);
  const t = parseIsoDate(to);
  if (!f || !t) return null;
  return Math.round((Date.UTC(t[0], t[1] - 1, t[2]) - Date.UTC(f[0], f[1] - 1, f[2])) / 86_400_000);
}

export function mifflinBmr(weightKg: number, heightCm: number, ageYears: number, sex: SexConstant): number {
  return 10 * weightKg + 6.25 * heightCm - 5 * ageYears + SEX_CONSTANT[sex];
}

export function roundToNearest10(kcal: number): number {
  return Math.round(kcal / 10) * 10;
}

export function proteinSuggestion(gPerKg: number, weightKg: number): number {
  return gPerKg * weightKg;
}

const LABEL = {
  weight: "weight",
  height: "height",
  dob: "date of birth",
  sex: "equation sex (choose male or female constant)",
} as const;

export function estimateEnergy(input: EnergyInputs): EnergyResult {
  const missing: string[] = [];
  const weight = input.weight_kg != null && input.weight_kg > 0 ? input.weight_kg : null;
  const height = input.height_cm != null && input.height_cm > 0 ? input.height_cm : null;
  if (weight == null) missing.push(LABEL.weight);
  if (height == null) missing.push(LABEL.height);

  let age: number | null = null;
  if (!input.date_of_birth) missing.push(LABEL.dob);
  else {
    age = ageInYears(input.date_of_birth, input.as_of);
    if (age == null) missing.push(LABEL.dob);
  }

  let sexConstant: SexConstant | null = null;
  let chosen = false;
  if (input.sex === "male" || input.sex === "female") sexConstant = input.sex;
  else if (input.equation_sex === "male" || input.equation_sex === "female") {
    sexConstant = input.equation_sex;
    chosen = true;
  } else missing.push(LABEL.sex);

  if (missing.length > 0 || weight == null || height == null || age == null || sexConstant == null) {
    return { ok: false, missing, message: `Can't calculate yet — missing ${missing.join(", ")}.` };
  }

  const warnings: string[] = [];
  if (age < 18) warnings.push("Mifflin-St Jeor is validated for adults; this client is under 18.");
  if (input.weighed_on) {
    const d = daysBetween(input.weighed_on, input.as_of);
    if (d != null && d > STALE_WEIGHT_DAYS) warnings.push(`Latest weight is ${d} days old (${input.weighed_on}).`);
  }
  if (!input.activity) warnings.push("Choose an activity level to get TDEE.");

  const bmr = mifflinBmr(weight, height, age, sexConstant);
  const factor = input.activity ? input.activity.factor : null;
  const tdee = factor != null ? bmr * factor : null;
  const protein =
    input.protein_g_per_kg != null && input.protein_g_per_kg > 0 ? proteinSuggestion(input.protein_g_per_kg, weight) : null;

  return {
    ok: true,
    bmr,
    tdee,
    bmr_display: roundToNearest10(bmr),
    tdee_display: tdee != null ? roundToNearest10(tdee) : null,
    age_years: age,
    sex_constant: sexConstant,
    sex_constant_chosen: chosen,
    factor,
    protein_g: protein,
    working: {
      as_of: input.as_of,
      weight_kg: weight,
      weighed_on: input.weighed_on,
      height_cm: height,
      date_of_birth: input.date_of_birth!,
      age_years: age,
      sex: input.sex,
      sex_constant: sexConstant,
      activity: input.activity,
      protein_g_per_kg: input.protein_g_per_kg,
    },
    warnings,
  };
}

/** Row shape returned by the client_energy_inputs(client_id, as_of) RPC. */
export type ClientEnergyInputsRow = {
  client_id: string;
  as_of: string;
  weight_kg: number | string | null;
  weighed_on: string | null;
  height_cm: number | string | null;
  date_of_birth: string | null;
  sex: RecordedSex | null;
  equation_sex: SexConstant | null;
  activity_key: string | null;
  activity_label: string | null;
  activity_factor: number | string | null;
  protein_g_per_kg: number | string | null;
};

const num = (v: number | string | null): number | null => (v == null || v === "" ? null : Number(v));

/** Adapter: the RPC row → EnergyInputs (Postgres numerics may arrive as strings). */
export function energyInputsFromRow(row: ClientEnergyInputsRow): EnergyInputs {
  const factor = num(row.activity_factor);
  return {
    as_of: row.as_of,
    weight_kg: num(row.weight_kg),
    weighed_on: row.weighed_on,
    height_cm: num(row.height_cm),
    date_of_birth: row.date_of_birth,
    sex: row.sex,
    equation_sex: row.equation_sex,
    activity:
      row.activity_key && factor != null
        ? { key: row.activity_key, label: row.activity_label ?? row.activity_key, factor }
        : null,
    protein_g_per_kg: num(row.protein_g_per_kg),
  };
}
