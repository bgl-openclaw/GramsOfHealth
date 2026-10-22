# Requests for the research workstream (22 October 2026)

Paste the block below into the window that maintains the workbooks. The app loads each workbook as it is (scripts/reference/import_reference.py), so overlaps and missing columns have to be fixed in the workbooks themselves.

```text
The app now loads marker_ranges_dietitian_decides.xlsx and meal_plan_logic_dietitian_decides.xlsx as they are. Dietitians decide in the app, and a re-import keeps decisions on unchanged rows. Three requests:

A. REMOVE OVERLAPPING QUESTIONS. Each question should be asked once only.
1. Saturated fat is asked three times:
   - D5 ("pick one: 10% or 8-10%")
   - Targets and ranges → satfat_energy (note "Dietitian to choose")
   - Plan rules → satfat_emphasis (default "<= 10% of energy weekly")
   Keep the satfat_energy target row as the only place the number is set: Upper 10, note "8-10% on another NHMRC page; Edit to use 8". Delete D5. Change the satfat_emphasis default to "uses the saturated fat target (Targets and ranges)".
2. The discretionary allowance is asked twice: D12 and the Targets and ranges → discretionary row. Keep D12 (the practice's allowance). Delete the discretionary target row and move its source notes into D12.
3. Vegetarian iron and zinc: D4 and the Plan rules → iron_pairing default ("vegetarian iron NRV x1.8"). Keep D4. Change the iron_pairing default to "uses the vegetarian iron decision (D4)".
4. Sodium: D6 (2017 values or the 2026 draft), the sodium NRV rows, Targets → sodium_sdt, and the Plan rules → sodium_cap default (2,000 mg). Keep D6 for which version applies. Keep the values in their rows. Change the sodium_cap default to "uses the sodium target (Targets and ranges)", so the 2,000 mg number lives in one place.
5. "Check against" on every NRV row repeats D1. Pre-fill that column with D1's suggestion (RDI where there is one, otherwise AI), so the dietitian only changes exceptions. Add fibre to D1's text: aim for the AI or the SDT (28/38 g)?
6. D9 (which ULs are soft) overlaps the magnesium and phosphorus rows. Keep D9 as the decision. In those rows, point to D9 in the note instead of asking again.
Also: the Planner set-up page no longer asks about the protein/fat/carbohydrate energy split or treats. Those are decided only here (Targets and ranges, D12).

B. COLUMNS THE RESULTS READER NEEDS
The PDF reader matches what a lab prints to a marker, so it needs these on Marker decisions. Add them as reference (green) columns, before the yellow ones:
- "Names printed on reports": every name and abbreviation labs use, separated by ";" (e.g. Ferritin; FERR; Serum ferritin).
- "Units printed on reports" with the conversion to the marker's unit (e.g. mg/dL x 0.0555 = mmol/L for glucose).
- "Plausible low" and "Plausible high": outside these, a number is almost certainly a reading error, not a result.
On Ranges by age, add a "Row ID" column (R001, R002 …) that never changes once given, even if the row's values change. Today rows are matched by marker + population + sex + ages + pregnancy + range type + source; if any of those wording changes, the row looks new and loses its decision.
Nothing has been decided yet, so adding columns now costs nothing.

C. DEXA WORKBOOK
Make dexa_ranges_dietitian_decides.xlsx with exactly the same tabs and column names as marker_ranges_dietitian_decides.xlsx (Read me, Ranges by age, Marker decisions, Change log, Sources), including the B columns. The same importer can then load it.
- Marker codes start with dexa_ (e.g. dexa_body_fat_pct, dexa_vat_mass, dexa_almi, dexa_bmd_lumbar_t).
- Cover what reports print, for both Hologic and GE Lunar where they differ:
  - total and regional fat, lean and bone mass (arms, legs, trunk, android, gynoid), body fat %, A/G ratio
  - visceral fat (mass, volume, area)
  - appendicular lean mass index and fat mass index
  - BMD at lumbar spine L1-L4, femoral neck and total hip, with T-scores and Z-scores
- Range types: use the same vocabulary, and add any DEXA ones you need, e.g. "Classification (WHO T-score)" or "Manufacturer reference database (not Australian)". Flag non-Australian reference data the same way the blood workbook does.
- Same food action / refer to GP / retest columns per marker.
```

## Addendum: names and units seen on a Laverty Pathology report (22 Oct 2026)

From an anonymised Laverty cumulative report. Add these to "Names printed on reports" and "Units printed on reports" on Marker decisions. Paste into the research window together with the block above.

```text
D. NAMES AND UNITS LAVERTY PRINTS (from a real report layout, details removed)
Names printed → marker:
- Chol → total_cholesterol
- Trig → triglycerides
- HDL → hdl_c
- LDL → ldl_c
- Non-HDL → non_hdl_c
- Serum 25(OH) Vitamin D → vitamin_d
- HbA1c- IFCC (mmol/mol) and HbA1c- NGSP (%) → hba1c
- CRP → crp
- TSH → tsh
- Iron → serum_iron
- T'ferrin → transferrin
- T. Sat. → transferrin_sat
- Ferritin → ferritin
- Na → sodium; K → potassium; Cl → chloride; HCO3 → bicarbonate
- Urea → urea; Creat → creatinine
- eGFR → egfr
- Bili → bilirubin; AST, ALT, GGT → ast, alt, ggt; Alk Phos → alp
- Protein → total_protein; Albumin → albumin
- Ca → calcium; Corr Ca → calcium_adjusted
- PO4 → phosphate; Mg → magnesium
- Hb → haemoglobin; Hct → haematocrit; MCV → mcv

Units as printed:
- umol/L = µmol/L; ug/L = µg/L; mIU/L = mU/L; mL/min/1.73sqM = mL/min/1.73m²
- Hct is printed with no unit (L/L implied): allow "no unit printed" for haematocrit.
- HbA1c % (NGSP) → mmol/mol (IFCC): IFCC = (NGSP − 2.15) × 10.929, i.e. factor 10.929, offset −23.5.
- Transferrin is printed in umol/L, but the marker unit is g/L. Give the exact conversion, or add umol/L as the marker's unit.

Fix in the marker list:
- calcium and calcium_adjusted are both named "Calcium". Name the second "Calcium (corrected)" so they can be told apart.
- Decide whether to track the tests the report prints that aren't on the list: anion gap, globulin, RCC, MCH, MCHC, RDW, WBC and differential (neutrophils, lymphocytes, monocytes, eosinophils, basophils), platelets, cholesterol/HDL ratio.
```
