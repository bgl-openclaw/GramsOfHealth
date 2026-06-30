# Grams of Health — design system & reusable patterns

From the Claude Design v2 handoff (`design_v2/` — Recipe Editor + Recipes Browser).
These tokens and patterns apply **across the whole app**, not just Recipes.
Attach the two `.dc.html` files to Lovable for pixel fidelity.

## 1. Global tokens (apply to EVERY screen + login + A4 card + PDF renderer)
- **brand-green `#003018`** — primary actions, brand, focus rings, verified ticks, selected/on chips, slider fill. (Replaces the old `#2f7a4d` as the primary — update everywhere.)
- brand-green-hover `#0c4a2c`; **green-mid `#2f7a4d`** — contribution bars, confirmed-tag check, kcal value text.
- **coral `#ef835c`** — section underline rules, "needs review" dot, saved-view ★. Soft: bg `#fdf3ee`, border `#f2d9cc`, text `#9c5440`.
- green-tint bg `#eef3ef` (active chip / verified pill / nav-active), border `#cddbd2`/`#bcd4c4`, text `#20422f`.
- paper `#f4f3ef`, card `#fff`, card-soft `#fcfcfa`; ink `#1c2019`, ink-soft `#5c625b`, ink-muted `#6b716c`, ink-faint `#9aa093`; line `#e6e4de`, field-border `#e0ded7`; danger `#c0584e`.
- **Type:** IBM Plex Sans (UI) + IBM Plex Mono (**all numbers** — macros, qty, kcal, serves, time, counts, badges). h1 28/600/-0.02em; macro value mono 27/600; panel h2 16–17/600; body 13–14; chips 12–12.5/500–600; overlines 10.5–11/600/+0.07em/UPPERCASE/ink-faint.
- **Shape:** radius — cards 16, popover/table 13–14, buttons/inputs/chips 9–11, tags 6–8, pill 20. Borders 1px (1.5 emphasis). Shadows sparingly (sticky `0 6px 20px -16px rgba(28,32,25,.4)`; popover `0 18px 44px -18px`; drawer `-16px 0 44px -22px`).

## 2. Reusable patterns
- **Browse template** — header (title + mono "Showing X of Y" + Table/Grid toggle + "+ New") · toolbar (search + quick-filter buttons + "Filters" button with mono count badge) · saved-views row · active-filter chips row (+ Clear all) · results table/grid · **slide-in Filters drawer** (right, 432px, scrim; grouped sections; footer Clear all + "Show N").
- **Filters drawer rule** — raw macro **ranges live on dual-handle sliders**; clinical **presets live under "Goals"** chips, kept SEPARATE from the ranges (the old screen wrongly mixed them).
- **Three-tier tags + inline confirm** — (1) Course = solid chip; (2) Confirmed diet = white chip + green-mid check; (3) Suggested = **dashed italic** + inline **✓ accept** / **✕ dismiss**. Accept → confirmed; dismiss → removed. No navigation.
- **Status pill** — one pill: Verified (green-tint) / Needs review (coral-soft).
- **Saved views** — starable, selectable pills.

## 3. Where each pattern applies (the cross-site map)
| Pattern | Recipes | Foods | Media | Clients | Plans | Quality |
|---|---|---|---|---|---|---|
| Tokens | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Browse template | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| Filters drawer | ✓ macros/goals/time/status/class | ✓ source/aisle/dietary/per-100g/status | used·unused, aisle | restriction | client | — |
| Tags + accept/dismiss | ✓ diet suggestions | ✓ **food dietary flags** (auto→confirm) | — | — | — | surfaces unconfirmed |
| Status pill | ✓ | ✓ verified | — | — | — | ✓ |
| Saved views | ✓ | optional | — | optional | — | — |

The standout reuse: the **suggested-tag accept/dismiss** is the perfect UI for confirming our auto-seeded **food dietary flags** — same gesture, on each food's Dietary tab.

## 4. Prompts

### 4a. Global design system (run first; re-skins everything)
```text
Adopt the Grams of Health design system globally — update the theme/Tailwind tokens and use them on every screen, login, the A4 card, and any PDF/print route. Primary brand colour moves from the old #2f7a4d to brand-green #003018 (update everywhere). Tokens: brand-green #003018, hover #0c4a2c, green-mid #2f7a4d (bars/kcal/confirmed-check), coral #ef835c (+ soft bg #fdf3ee / border #f2d9cc / text #9c5440), green-tint #eef3ef (border #cddbd2, text #20422f), paper #f4f3ef, card #fff, card-soft #fcfcfa, ink #1c2019 / soft #5c625b / muted #6b716c / faint #9aa093, line #e6e4de, field-border #e0ded7, danger #c0584e. Fonts IBM Plex Sans (UI) + IBM Plex Mono (ALL numbers). Radii: cards 16, popover/table 13–14, controls 9–11, tags 6–8, pill 20. Keep shadows subtle (sticky/popover/drawer values in the design). Don't change any logic — visual only.
```

### 4b. Reusable browse layout (apply to Recipes, Foods, Media, Clients, Plans)
```text
Build one reusable "browse" layout and use it on Recipes, Foods, Media, Clients, Plans. Structure: header (title + mono "Showing X of Y" + Table/Grid toggle + "+ New …"); toolbar (search flex-1 + quick-filter buttons [status dot + label; on = green-tint bg/border] + a "Filters" button [green-tint bg, brand-green border] with a brand-green mono count badge when filters are active); a saved-views row (coral ★ starred, green-tint selected, dashed "+ Save current"); an active-filters row when active ("Active:" + removable chips + "Clear all" danger); a results table (card radius 14, mono numbers, row hover #fbfbf8, right-aligned row actions); and a right slide-in Filters drawer (432px, scrim; "Filters" + coral rule + ✕; grouped sections divided by line-soft; footer "Clear all" + primary "Show N"). 
- RECIPES: use the attached Recipes Browser.dc.html as the pixel spec. Drawer: Nutrition (5 REAL dual-handle range sliders Cal/Protein/Carbs/Fat/Fibre), Goals (High protein/High fibre/Low-carb/Heart-healthy/Balanced/Diabetes-friendly — SEPARATE from the ranges), Time & servings, Status, Classification (Course/Cuisine/Diet/Meal). Columns: Title(+tags) · Serves · Time · Kcal/serve (green-mid) · Status pill · Updated · actions.
- FOODS: same shell. Quick-filters Verified / Needs review. Drawer: Source (Mine/AFCD), Aisle, Dietary (food flags), Per-100g macro ranges (sliders), Status. Columns: Name(+dietary chips) · source · kcal/100g · P/F/C/Fibre · aisle · Status pill · actions.
- MEDIA / CLIENTS / PLANS: same shell, lighter filters (Media: used/unused + aisle; Clients: restriction; Plans: client).
Macro filters are computed live via the engine; dietary filters via the food-flag logic (Step 4b). Grams-first throughout.
```

## 5. Consolidated filtering + pattern plan (run in Lovable PLAN MODE)
Refinements vs the raw design: (1) **Diet split out of Classification** into its own computed **Dietary** section (full allergen-free set, from food flags); (2) **Foods gets full filters + saved views + a "Missing macros" quick-filter** (drives the dietitian verification pass); (3) **Quality is a dashboard**, not a browse screen.

```text
PLAN ONLY — do not write code. Produce an implementation plan for one consolidated filtering + browse system across Recipes, Foods, Media, Clients, Plans, using our design system + existing Supabase backend. Attach Recipes Browser.dc.html as the pixel spec.

DESIGN: v2 tokens (brand-green #003018, green-mid #2f7a4d, coral #ef835c, green-tint #eef3ef…), IBM Plex Sans + Mono (mono for all numbers). One reusable Browse layout: header (title + mono "Showing X of Y" + Table/Grid toggle + "+ New"); toolbar (search + quick-filter buttons + "Filters" button with mono active-count badge); saved-views row; active-filter chips row (+ Clear all); results table/grid; right slide-in Filters drawer (432px + scrim; grouped sections; footer Clear all + "Show N"). Raw macro ranges = dual-handle sliders; clinical presets = "Goals" chips kept SEPARATE from ranges.

BACKEND (exists — compute live, don't store): macro filters via the engine (grams-first); dietary suitability computed from food_diet_flags; tags in tags/recipe_tags (source auto/manual); foods.aisle; recipes/foods.verified.

RECIPES (/recipes): quick-filters Needs review · Verified · Has photo. Drawer — Nutrition/serve (dual sliders Calories/Protein/Carbs/Fat/Fibre); Goals (High-protein, High-fibre, Low-carb, Heart-healthy, Balanced, Diabetes-friendly — separate from ranges); Dietary (computed from flags: Vegetarian, Vegan, Pescatarian, Gluten-free, Dairy-free, Egg-free, Nut-free, Shellfish-free, Fish-free, Soy-free, Sesame-free, Low-FODMAP); Classification (Course, Cuisine, Meal); Time & servings (≤15/≤30/≤45/45+ · 1–2/3–4/5+); Status. Saved views: yes. Columns: Title(+tags) · Serves · Time · Kcal/serve · Status pill · Updated · actions. Table default.

FOODS (/foods): quick-filters Verified · Needs review · Missing macros. Drawer — Source (My library / AFCD / Custom); Aisle (Produce/Dairy & eggs/Meat & seafood/Bakery/Pantry/Frozen/Drinks); Contains (food flags: meat, fish, shellfish, dairy, egg, gluten, tree nut, peanut, soy, sesame, honey, high-FODMAP); Nutrition/100 g (dual sliders Energy/Protein/Fat/Carbs/Fibre); Status (Verified/Needs review/Has density). Saved views: yes. Columns: Name(+dietary chips) · Source · kcal/100g · P/F/C/Fibre · Aisle · Status pill · actions. Table default.

MEDIA (/media): quick-filter Unused; search filename; drawer light (Used/Unused). Grid default.
CLIENTS (/clients): search name; drawer light (Restriction, Has active plan). Table.
PLANS (/plans): search title; drawer light (Client). Table.
QUALITY (/quality): NOT a browse screen — a dashboard of issue lists using the Status pill, no filter drawer.

PATTERN → SCREEN MAP: Browse template + Filters drawer → Recipes/Foods (full), Media/Clients/Plans (light), Quality = dashboard. Quick-filters → Recipes, Foods, Media. Three-tier tags + inline ✓accept/✕dismiss → Recipes (diet suggestions: recipe_tags source auto→manual) AND food Dietary tab (confirm auto-seeded flags); Quality surfaces unconfirmed. Status pill (Verified/Needs review) → Recipes, Foods rows, Quality. Saved views → Recipes, Foods. Grid/Table toggle → Recipes (table default), Foods (table), Media (grid default).

Deliver a plan: the shared components (Browse layout, FilterDrawer, dual RangeSlider, TagChip with accept/dismiss, StatusPill, SavedViews, QuickFilter), the data/compute each filter needs, and the build order. No code yet.
```

### 4c. Three-tier tags + accept/dismiss + status pill (Recipes browser AND food Dietary tab)
```text
Reuse the three-tier tag + status pill everywhere relevant. Course tag = solid chip (#f0efe9 bg, ink-soft, 11.5/600, radius 6). Confirmed diet = white chip, border #bcd4c4, green-tint-text, small green-mid check. Suggested = DASHED border #cfcdc3, bg #faf9f6, italic muted text + inline ✓ accept (#e4efe6 bg, green-mid; hover solid green) and ✕ dismiss (#f0efe9, faint; hover coral). 
- Recipes browser: suggested = recipe_tags.source='auto'; accept → set source='manual'; dismiss → delete recipe_tag. No navigation.
- Food Dietary tab (/foods/$id): show the food's auto-seeded dietary flags as suggested chips with the same ✓/✕; accept confirms the flag, dismiss clears it. (This is how the dietitian verifies food flags fast.)
Status pill — one pill (Verified green-tint / Needs review coral-soft) — on recipe rows and food rows, driven by the verified field.
```
