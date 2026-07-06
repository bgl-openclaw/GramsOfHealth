# Handoff: Grams of Health — Recipe Editor & Recipes Browser

## Overview
Two screens for the Grams of Health internal dietitian tool (Phase 2 + a Recipes-browser redesign):

1. **Recipe Editor** — where a dietitian builds or edits a recipe and watches its five macros (Calories, Carbs, Protein, Fat, Fibre) recalculate live as they change a quantity, size or ingredient. Includes a per-ingredient macro-contribution column, create-a-food and create-a-size flows, method steps, and duplicate-to-variant.
2. **Recipes Browser** — a redesign of the recipe-list screen, moving a 70-chip filter wall into a grouped slide-in panel, adding active-filter chips, saved views, and a cleaner three-tier tag system with inline accept/dismiss for auto-suggested diet tags.

Both map directly onto the existing Supabase schema (`foods`, `unit_conversions`, `recipes`, `ingredient_lines`, `method_steps`, `afcd_master`). The live macro maths is a direct port of the seed `recalc_engine.py`.

---

## About the design files
The files in this bundle are **design references created in HTML** — streaming "Design Component" (`.dc.html`) prototypes that show the intended look and behaviour. **They are not production code to copy directly.**

Each `.dc.html` is a single file with three logical parts wrapped by a small runtime (`support.js`):
- the **template** (markup between `<x-dc>…</x-dc>`),
- a **logic class** (`class Component extends DCLogic { renderVals() {…} }`) that returns the template's data + handlers,
- a **props/Tweaks** JSON block.

The task is to **recreate these designs in the target codebase's environment**. The roadmap specifies **React (via Lovable) + Supabase + a portable TypeScript recalculation engine** ported from `recalc_engine.py`. Build with that stack and its established patterns/components — use the HTML purely as the visual + interaction spec. The recalculation logic shown in the editor's logic class is the reference for the TS engine; the seed `recalc_engine.py` is the source of truth.

## Fidelity
**High-fidelity.** Final colours, typography, spacing, and interactions. Recreate pixel-for-pixel using the codebase's component library. Designs are laid out for **desktop** (≈1440px wide content), single-user, internal. No mobile breakpoints were designed; treat as desktop-first.

Two practical caveats, called out where relevant below:
- The macro **range sliders** in the Browser's filter panel are **visual placeholders** (static thumb positions). Implement as real dual-handle range inputs.
- The recipe **photos** are striped placeholders. Real images come from Supabase Storage (`recipes.image_url_1` / `image_url_2`).

---

## Design tokens

### Colour
| Token | Hex | Use |
|---|---|---|
| `brand-green` | `#003018` | Primary actions, brand, focus rings, verified ticks, selected state, slider fill, filter-on chips |
| `brand-green-hover` | `#0c4a2c` | Hover for primary buttons |
| `green-mid` | `#2f7a4d` | Contribution bars, confirmed-tag check, kcal value text |
| `coral` | `#ef835c` | Accent rules (section underlines), "needs review" status dot, saved-view star |
| `coral-soft-bg` | `#fdf3ee` | Needs-review pill background |
| `coral-soft-border` | `#f2d9cc` | Needs-review pill border |
| `coral-text` | `#9c5440` | Needs-review pill text |
| `green-tint-bg` | `#eef3ef` | Active/selected chip bg, verified pill bg, nav-active bg |
| `green-tint-bg-2` | `#f3f7f3` | Light green hover/fill |
| `green-tint-border` | `#cddbd2` / `#bcd4c4` | Tint chip/pill borders |
| `green-tint-text` | `#20422f` | Text on green tints |
| `paper` | `#f4f3ef` | App background |
| `card` | `#ffffff` | Panels, cards, bars |
| `card-soft` | `#fcfcfa` / `#faf9f6` | Input fields, inset areas |
| `ink` | `#1c2019` / `#20251f` | Primary text |
| `ink-soft` | `#5c625b` | Secondary text |
| `ink-muted` | `#6b716c` | Tertiary / labels |
| `ink-faint` | `#9aa093` / `#a7aca0` | Captions, column labels, placeholders-ish |
| `line` | `#e6e4de` | Card borders |
| `line-soft` | `#efeee8` / `#f2f1ec` / `#f4f3ee` | Inner dividers, row separators |
| `field-border` | `#e0ded7` / `#e8e6df` | Input borders |
| `danger-text` | `#b5675a` / `#c0584e` | Clear-all / delete hover |
| `placeholder` | `#aeb2ab` | Input placeholder text |

### Typography
- **Sans (UI):** `'IBM Plex Sans', system-ui, sans-serif` — weights 400/500/600/700.
- **Mono (numbers/data):** `'IBM Plex Mono', monospace` — weights 400/500/600. Used for ALL numeric values (macros, quantities, kcal, serves, time, counts, badges).
- Antialiased (`-webkit-font-smoothing: antialiased`).

Type scale (px / weight / tracking):
- Page title `h1`: 28 / 600 / -0.02em
- Recipe title input: 28 / 600 / -0.02em
- Macro value (mono): 27 / 600 / -0.02em
- Panel `h2`: 16–17 / 600 / -0.01em
- Body / inputs: 13–14 / 400–500
- Chips / pills: 12–12.5 / 500–600
- Column labels / overlines: 10.5–11 / 600 / +0.07em / UPPERCASE / colour `ink-faint`
- Captions: 11.5–12 / 400 / `ink-faint`

### Spacing & shape
- Card radius: **16px** (panels), **13–14px** (popovers/tables), **9–11px** (buttons/inputs/chips), **6–8px** (tags/small controls), **20px** (pill / saved-view).
- Card padding: 18–22px. Row padding: 6–15px vertical, 20–22px horizontal.
- Gaps: 8–16px common; grid gap 9–14px.
- Borders: 1px solid (1.5px for emphasis dividers, 2px for slider thumbs).
- Standard control heights: buttons 36–42px; inputs ~38–42px.
- Shadows (sparingly):
  - Sticky bar: `0 6px 20px -16px rgba(28,32,25,0.4)`
  - Popover: `0 18px 44px -18px rgba(28,32,25,0.5)`
  - Drawer: `-16px 0 44px -22px rgba(28,32,25,0.5)`
  - Slider thumb: `0 1px 4px rgba(0,0,0,0.15)`
  - Scrim: `rgba(28,32,25,0.28)`

### Icons
Inline SVG, 1.2–1.4 stroke width, `currentColor` or `ink-faint`. Simple line icons (search, clock, camera, trash, duplicate, file, chevron, check, filter-lines, grid/table). A checkmark path used throughout: `M2.5 6.3 L4.8 8.6 L9.5 3.4`.

---

## Screen 1 — Recipe Editor (`Recipe Editor.dc.html`)

### Purpose
Build/edit one recipe; see its five per-serve macros update live on every edit.

### Layout
Vertical stack on `paper` background:
1. **Sticky app bar** (h 58px, `card`, bottom `line`): logo (left) · divider · "Recipe editor" · spacer · "All changes saved" (green dot) · **Duplicate to variant** (outline button) · **Save recipe** (primary `brand-green`).
2. Centred content column, `max-width: 1400px`, padding `22px 26px 90px`.
3. **Header band** (`card`, radius 16, padding 20, flex row, gap 22):
   - Left: two photo slots — primary `188×142` (striped placeholder, camera icon, mono "hero photo" caption) + secondary `96×142` (dashed, "+ 2nd photo").
   - Right (flex-1, column): overline "RECIPE TITLE"; large editable **title input** (28/600, border-bottom turns `brand-green` on focus); a **"Show macros on export"** checkbox (custom 18px box, checked = `brand-green` fill + white tick) top-right; meta row at bottom — **Serves stepper** (− value + in a bordered group) · **Time field** (clock icon + mono number + "min") · two mono info pills ("14 ingredients", "4 steps").
4. **Sticky macro strip** (`card`, radius 16, `top: 58px`, z 30, shadow): left label block ("MACROS" overline + 18px coral rule + "Per serve · updates live"); five **macro tiles** (flex, equal); right **basis toggle** (segmented "Per serve" / "Recipe total"). Each tile: label (12/600), big mono value (27px), unit (kcal/g); Carbs tile has sub-caption "excl. fibre". The tile for the currently-shown contribution macro gets bg `#f1f8f2`, border `#bcdcc4`, green label, and a "SHOWN" mini-badge.
5. **Body grid**: `grid-template-columns: 1.42fr 1fr; gap: 16px; align-items: start`.
   - **Left — Ingredients panel** (`card`): header ("Ingredients" + coral rule + subtitle) with the **contribution control** on the right (label "Show contribution" + toggle switch + macro `<select>`; when on, control bg/borders go green); a column-label row; the ingredient rows; an optional contribution **total foot**; and "+ Add ingredient" (green) / "+ Add section heading" (dashed) buttons.
   - **Right — Method panel** (`card`): header; ordered steps (24px mono number badge + drag handle + auto-grow textarea); "+ Add step"; and an **A4 card preview** placeholder (striped, "phase 3" tag) at the bottom.

### Ingredient row
CSS grid; columns change when the contribution column is shown:
- hidden: `22px 64px 152px minmax(150px,1fr) 150px 28px`
- shown: `22px 60px 152px minmax(130px,1fr) 118px 122px 28px`
- gap 9px, row padding `6px 20px`, hover bg `#fbfbf8`.

Cells, left→right:
1. **Drag handle** — `⠿`, colour `#cbcabf`, `cursor: grab`.
2. **Quantity** — mono input, right-aligned, bordered `field-border`, focus `brand-green`.
3. **Size** — `<select>` (AU units: tsp, tbsp, cup, g, kg, mL + the food's custom sizes like *medium, clove, ×95 g can, handful*) **plus** a 30px dashed "+" button that opens the **create-a-size** popover.
4. **Food** — button showing optional **verified tick** (15px `brand-green` circle + white check) + food name (ellipsised) + chevron; opens the **food picker** popover.
5. **Prep** — borderless input ("—" placeholder), hover/focus reveal field.
6. **Contribution** (conditional) — mono value + unit, and a 5px track (`#eeede7`) with a `green-mid` fill sized to the line's share of the largest line's contribution.
7. **Delete** — ghost trash button, hover bg `#f3eceb` + danger colour.

### Popovers (absolutely positioned under their trigger cell, z 50–51)
- **Create-a-size** (290px): title "Add a size" + "for {food} — every size resolves to grams"; fields Size name, Weight (mono), Unit (`g`/`mL`); Cancel / **Save size**.
- **Food picker** (320px): search field; scrollable list (max-h 232) of foods each with verified tick (solid green) or unverified marker (dashed circle) + name + mono kcal; sticky footer "**＋ Create a new food**" (green) → opens create-a-food.
- **Create-a-food** (340px): "Create a new food" + "Saves to the library and becomes reusable"; Food name; **PER 100 G** grid (Energy kcal, Protein, Fat, Carbs, Fibre, Density g/mL — all mono with unit suffix); helper "Carbs excludes fibre. Density is optional, for liquids."; Cancel / **Save to library**.

### Contribution total foot
Same grid; spans into the food column with "Total {Macro} {per serve|total}" and a right-aligned mono total in `brand-green`, on bg `#fafbf9`, top border 1.5px.

### Example content (use verbatim — the seed "Lentil Tuna Salad")
Serves 4 · 5 min · per-serve macros **369 kcal / 20 g carbs / 34 g protein / 15 g fat / 7 g fibre**. 14 ingredient lines:
`1 medium sweet potato (diced)` · `2 tsp olive oil` · `2 tsp mixed herbs, dried` · `1 tsp paprika` · `1 tsp salt` · `1 tsp pepper` · `2 tbsp sherry vinegar` · `1 tsp dijon mustard` · `2 clove garlic (minced)` · `2 tbsp olive oil` · `4 ×95 g can tuna, springwater (drained)` · `420 g brown lentils (drained)` · `250 g cherry tomatoes (halved)` · `1 handful parsley`.
Method (4 steps) is in the prototype's logic class.

---

## Screen 2 — Recipes Browser (`Recipes Browser.dc.html`)

### Purpose
Browse, search and filter the recipe library; verify auto-suggested diet tags; jump into the editor.

### Layout
Full-height flex row:
1. **Sidebar** (228px, `card`, right `line`): logo; nav — **Recipes** (active: `eef3ef` bg, `brand-green` text) · Foods · Media · Plans · Clients · Quality · Users; bottom — Collapse · email · Sign out.
2. **Main** (flex-1, `height: 100vh`, internal scroll):
   - **Header** (`padding: 24px 30px 0`): "Recipes" `h1` + "Showing **42** of 326 recipes" (mono count) · **Table/Grid** segmented toggle · **+ New recipe** (primary).
   - **Toolbar** (`padding: 18px 30px 0`): row of — search field (flex-1, radius 11) · three **quick-filter** buttons (Needs review / Verified / Has photo; each a coloured status dot + label; on-state = `eef3ef` bg, `cddbd2` border, coloured dot) · **Filters** button (`eef3ef` bg, `brand-green` border) with a `brand-green` mono **count badge** when filters are active.
   - **Saved views** row: "SAVED VIEWS" overline + pill buttons ("★ High-protein dinners" [coral star], "Quick lunches ≤ 30", "Needs review · 42" [selected]) + dashed "+ Save current".
   - **Active filters** row (only when active; top border): "Active:" + removable chips (`eef3ef` bg, label + 17px ✕ button that hovers to `brand-green`) + "Clear all" (danger text).
   - **Results table** (`card`, radius 14): header row + recipe rows.

### Results table
Grid columns: `minmax(150px,1fr) 58px 68px 86px 124px 70px 56px`, gap 12, row padding `15px 22px`, separators `#f4f3ee`, hover `#fbfbf8`.
Columns: **Title** (+ tags) · Serves (mono, centre) · Time (mono, centre) · **Kcal/serve** (mono, right, `green-mid`; em-dash `#c2c1b6` when null) · **Status** · Updated (mono, faint) · row actions (duplicate, open).

Title cell = recipe name (14/600) + small camera icon if it has a photo, with a **tag row** beneath.

### Tag system (the key redesign — three distinct kinds)
1. **Course** (e.g. Bowl, Soup, Salad, Curry, Stir-fry, Breakfast): solid chip — bg `#f0efe9`, text `ink-soft`, 11.5/600, radius 6.
2. **Confirmed diet** (e.g. Gluten-free, Pescatarian): white chip, border `#bcd4c4`, text `green-tint-text`, with a small `green-mid` check. Radius 6.
3. **Suggested diet** (awaiting dietitian confirmation): **dashed** border `#cfcdc3`, bg `#faf9f6`, *italic* muted text, followed by two inline buttons — **✓ accept** (bg `#e4efe6`, `green-mid`; hover solid green) and **✕ dismiss** (bg `#f0efe9`, faint; hover coral). Accept → tag becomes a Confirmed chip; dismiss → tag removed. This replaces the old repeated "SUGGESTED" label.

### Status pill (one pill, replacing red `0%` + separate badge)
- **Verified**: bg `eef3ef`, border `cddbd2`, text `green-tint-text`, `green-mid` dot.
- **Needs review**: bg `coral-soft-bg`, border `coral-soft-border`, text `coral-text`, `coral` dot.

### Filters drawer (slide-in, right, 432px, z 51; scrim z 50)
Header "Filters" + coral rule + ✕ close. Scrollable body, sections divided by `line-soft`:
- **Nutrition / per serve** — five **dual-handle range sliders** (Calories, Protein, Carbs, Fat, Fibre), each: label + mono range readout; 6px track `#eceae3`; `brand-green` fill between two 16px white thumbs (2px green border). *(Prototype thumbs are static — implement as real dual-range.)*
- **Goals** — "Clinical shortcuts — combine with the ranges above"; toggle chips: High protein, High fibre, Low-carb, Heart-healthy, Balanced, Diabetes-friendly. On = solid `brand-green`. **These are intentionally separate from the raw macro ranges** (the old screen mixed them).
- **Time & servings** — Time (≤15/≤30/≤45/45+) and Servings (1–2/3–4/5+) toggle chips.
- **Status** — Verified / Needs review / Has photo.
- **Classification** — labelled groups: Course, Cuisine, Diet, Meal (toggle chips). *(Note for migration: in the old screen "High fibre ≥8 g" was wrongly in the Fat row, and "Low-carb ≤20 g" duplicated the `<20` bucket — both fixed here: ranges live on sliders, presets live under Goals.)*
Footer: "Clear all" (danger) + **Show {count} recipes** (primary).

---

## Interactions & behaviour
- **Live recalculation (Editor):** every quantity/size/servings change recomputes all five macros + every contribution value instantly. Basis toggle divides totals by servings (Per serve) or not (Recipe total); the contribution column and its foot total follow the same basis. (Algorithm below.)
- **Contribution column:** the "Show contribution" toggle reveals the extra column; the macro `<select>` chooses which macro and also forces the toggle on. The matching macro tile highlights with a "SHOWN" badge.
- **Popovers** open anchored to their trigger, close on Cancel/Save; only one open at a time per row.
- **Filters drawer** opens from the Filters button / closes on scrim, ✕, or "Show N recipes".
- **Suggested tags** accept (→ confirmed) / dismiss (→ removed) inline, no navigation.
- **Active-filter chips** remove individually; "Clear all" empties them.
- **Hover states** on every interactive element (documented inline in the prototypes via `style-hover`). Buttons darken/tint; ghost icon buttons gain a soft bg.
- Transitions used: toggle switch `background .15s` + thumb `left .15s`. Keep transitions subtle (~150ms).

## Recalculation algorithm (port to TypeScript; seed `recalc_engine.py` is source of truth)
Australian measures: **tsp = 5 mL, tbsp = 20 mL, cup = 250 mL** (never US 15 mL). Resolve every line to grams, then `macro = per_100g_value × grams / 100`; sum; divide by servings for per-serve. **Carbs = available carbohydrate, excludes fibre; fibre is a separate field.**
`toGrams(food, qty, unit)`:
- `g` → qty; `kg` → qty×1000; fixed packs e.g. `x95g` → qty×95.
- volume unit (tsp/tbsp/cup/ml): if the food has a **density** (g/mL) → `qty × mL × density`; else look up a stored `unit_conversions` gram weight.
- any other descriptive/count unit (clove, medium, handful, slice…) → stored `unit_conversions` gram weight.
- no resolution → flag the line (cannot resolve to grams).
Round displayed macros to integers (per-serve headline). Contribution bar width = line's macro ÷ max line's macro.

## State management
**Editor:** `title`, `servings`, `timeMinutes`, `showOnExport`, `lines[] {food_id, qty, unit, prep}` (ordered, optional `section`), `steps[]` (ordered text), `showContribution`, `contribMacro`, `perServe`, plus transient popover state (`pickerRow`/`foodRow`/`sizeRow`). Foods + unit conversions come from the library; editing a food or adding a size **persists to the library and becomes reusable**.
**Browser:** `recipes[]` (each with course, confirmed[], suggested[] `{id,label,state}`, status, kcal, serves, time, updated, hasPhoto), `active[]` filter chips, `quick{}`, drawer toggle states (`goalsOn`, `timeOn`, `servOn`, `statusOn`, `classOn`), `filtersOpen`, plus saved views. Accept/dismiss mutate the recipe's tag arrays; filter result count is live.

### Maps onto Supabase
`recipes` (title, servings, time_minutes, show_macros_export, variant_of, image_url_1/2) · `ingredient_lines` (recipe_id, food_id, section, position, quantity, unit, prep_note) · `method_steps` (recipe_id, position, text) · `foods` (food_id, display_name, afcd_key, source `afcd|custom`, *_100g macros, density_g_ml, verified, match_note) · `unit_conversions` (food_id, unit, grams) · `afcd_master`. Duplicate-to-variant copies a recipe and sets `variant_of`.

## Assets
- `assets/grams-logo.webp` — Grams of Health logo (transparent PNG/WebP, deep-green wordmark + coral underline). Use the real brand asset from your codebase if one exists.
- **Fonts:** IBM Plex Sans + IBM Plex Mono (Google Fonts). Swap for the codebase's licensed copies if available.
- Recipe photos are placeholders here → Supabase Storage URLs in production.
- All icons are inline SVG (replace with the codebase's icon set).

## Files in this bundle
- `Recipe Editor.dc.html` — the editor prototype (template + logic; live recalc engine in the logic class).
- `Recipes Browser.dc.html` — the browser/list prototype (template + logic; tag + filter behaviour in the logic class).
- `support.js` — the prototype runtime (reference only; **do not port** — it just makes the `.dc.html` files run in a browser).
- `assets/grams-logo.webp` — logo asset.

To view a prototype: open the `.dc.html` file in a browser. To read the intended data + handlers, look at the `class Component extends DCLogic` block near the bottom of each file.
