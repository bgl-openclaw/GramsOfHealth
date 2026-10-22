# Clinical reference data (from 22 October 2026)

Home for the two workbooks prepared for the dietitians:

| Workbook | Loaded into | Rows |
|---|---|---|
| `marker_ranges_dietitian_decides.xlsx` | `clinical_markers` (49 blood markers), `marker_ranges` (311), `reference_sources` (27) | 387 |
| `meal_plan_logic_dietitian_decides.xlsx` | `nutrient_reference_values` (310, 14 nutrients), `nutrition_targets` (11), `plan_rules` (9), `reference_decisions` (D1–D12), `reference_sources` (12) | 354 |

Migration `0051_clinical_reference.sql` (live), test `tests/sql/clinical_reference_0051.test.sql`.

## How it works

- **Reference values (the green columns)** come only from the workbooks, through `scripts/reference/import_reference.py`. The app can't change them.
- **Decisions (the yellow columns)** are made in the app (Settings → Clinical reference, Lovable prompt `docs/lovable-prompts/K1-clinical-reference.txt`).
  - Admins and dietitians decide; interns can comment.
  - Every change is stamped (who, when) and logged in `reference_change_log`, with an optional "why".
- **Nothing is active until decided.** The planner and the results reader will read only the `active_*` views:
  - rows a dietitian agreed to, or edited with the practice's own values;
  - and only while the reference row hasn't changed since.

## When the workbooks change

```bash
python3 scripts/reference/import_reference.py plan  <workbook.xlsx> ...   # what would change, writes nothing
python3 scripts/reference/import_reference.py apply <workbook.xlsx> ...
```

- **Unchanged rows** keep their decisions.
- **Changed rows** go to `changed`: inactive until re-decided, with the old values kept in `previous_ref`.
- **Rows no longer in the workbook** are retired, never deleted.
- **Filled-in yellow cells** in a workbook are reported, not imported, because decisions live in the app.

Rows are matched by key:
- **ranges:** marker | population | sex | age from | age to | pregnancy | range type | source, with #2, #3 … for exact repeats;
- **NRVs:** nutrient | life stage | sex | status;
- **targets:** code | life stage | sex;
- **rules and markers:** code;
- **decisions:** D-number.

Keep those columns stable in the workbooks, or a row looks new. Adding a "Row ID" column would make this sturdier.

Values that aren't plain numbers are kept exactly as printed. Simple limits are also read as numbers ("<4.0" as an upper limit, ">=7.0" as a lower one); everything else waits for the dietitian's practice value. Lists are in `seed/reference/*_parse_notes.csv`:
- ranges: 77 (43 of them read as limits);
- NRVs: 159 (e.g. "Not set", "460-920").

## Findings from the first read (22 Oct)

1. **No DEXA markers.** The marker list is bloods only. The results reader needs DEXA markers (body fat %, lean and fat mass, bone density with T and Z scores, visceral fat) before it can read DEXA reports.
2. **The reader also needs, per marker:** the names and abbreviations labs print, and plausibility limits. Not in the workbook; to be drafted for dietitian approval when the reader is built.
3. **Overlaps with the Planner set-up review page:**
   - protein/fat/carb energy split (AMDR), here in Targets and ranges;
   - treats (discretionary serves), here in D12;
   - the protein floor, here in D11.

   Each should be decided in one place.
4. **Not in the food library yet:**
   - vitamin C, vitamin D, iodine, phosphorus (D10);
   - folic acid (D3).

   AUSNUT 2023 has vitamin C and phosphorus, so they can come in with the AUSNUT import.
5. **The workbook itself flags rows to check against original papers:**
   - ALT, AST, GGT and bilirubin;
   - the WHO 2024 haemoglobin cut-offs.
