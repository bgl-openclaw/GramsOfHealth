# Build prompt — Grams of Health recipe-card PDF template

## What I want you to build
Recreate the attached design as a **reusable A4 recipe-card component** that our meal-planner renders to PDF — one card per recipe, identical every time. This single template is the layout behind **every** PDF the planner produces.

## About the attached file
`Recipe Card Template.dc.html` is a **visual + layout reference**, not production code.
- It is a self-contained HTML prototype. **Ignore the prototype harness**: the `support.js` script, the `<x-dc>` wrapper, the `{{ ... }}` template holes, the `<sc-for>` / `<sc-if>` tags, and the `data-props` JSON. Those are just how the mock runs in a browser.
- Read it for **layout, spacing, colours, typography, and the data shape**. The `class Component extends DCLogic { renderVals() {…} }` block near the bottom shows the exact data the card consumes and the fallback/sample content.
- **Recreate it as a real component in our stack** using our existing patterns and component library — do not ship the HTML or port the harness.

Fidelity: **high**. Match it closely — colours, type, spacing, the green macro footer, the coral accent rules.

## Stack
React (Lovable) + Supabase (Postgres + Storage). The card data comes from Supabase; the macros come from our recalculation engine (a TypeScript port of `seed/recalc_engine.py`). If any of these don't exist yet, scaffold the component with the prop contract below and stub the data source.

## Component & data contract
Build `<RecipeCard recipe={Recipe} />`. Props (with the Supabase mapping):

| Prop | Type | Source |
|---|---|---|
| `title` | string | `recipes.title` (main line, e.g. "Spinach & Feta Turkey Meatballs") |
| `subtitle` | string | optional accent line, e.g. "with Herbed Quinoa" (render in mid-green) |
| `serves` | number | `recipes.servings` |
| `timeMinutes` | number | `recipes.time_minutes` → render as "5 minutes" (singular at 1) |
| `photo` | string \| null | Supabase Storage URL (`recipes.image_url_1`); null → striped placeholder |
| `showMacros` | boolean | `recipes.show_macros_export` — hides the green macro footer when false |
| `ingredients` | `{ q: string; name: string }[]` | `ingredient_lines`: `q` = quantity + size (e.g. "½ cup"); `name` = food + prep (e.g. "feta cheese (crumbled)") |
| `steps` | `string[]` | `method_steps.text` ordered by `position` (component numbers them) |
| `macros` | `{ label: string; value: string }[]` | engine output, per serve — exactly five: Calories, Carbs, Protein, Fat, Fibre |

## Macros are computed, never stored
Per-serve figures come from the recalculation engine, not a database column. Non-negotiable rules (see `seed/recalc_engine.py`):
- Resolve every ingredient line to **grams** first, then `macro = per_100g_value × grams / 100`, sum, divide by `servings`.
- **Australian measures only:** tsp = 5 mL, tbsp = 20 mL, cup = 250 mL (never US 15 mL tbsp).
- **Carbs = available carbohydrate, excludes fibre.** Fibre is its own figure.
- Display rounded to integers; grams figures carry a "g" suffix, Calories none.

## Layout spec (from the reference — "2C")
- **Page:** A4 portrait, **794 × 1123 px @96dpi** (210 × 297 mm). White card, full-bleed in print.
- **Header:** logo top-**left**; title block top-**right**, right-aligned (Oswald 700, uppercase, deep green `#003018`, with the subtitle in mid-green `#2f7a4d`). Serves + time beneath the title, right-aligned, separated by a small coral dot. Hairline divider below.
- **Body:** two columns, `280px | 1fr`, gap 36px. **Left:** the single photo (rounded 12px, ~188px tall) then INGREDIENTS (bulleted; quantity in mono `#003018`). **Right:** DIRECTIONS — numbered steps with deep-green circular number badges. Each section heading is Oswald uppercase with a 30px coral underline (`#ef835c`). The body **flexes** to absorb longer lists.
- **Footer:** full-width deep-green band (`#003018`) with a 4px coral top rule; five evenly-spaced macro cells (uppercase muted-green label + mono white value), hairline dividers between. Hidden when `showMacros` is false.

## Design tokens
- Colours: deep green `#003018` (primary, title, badges, footer), mid green `#2f7a4d` (subtitle, accents, bullets), coral `#ef835c` (rules/accents), ink `#1c2019` / `#3a4137`, muted `#4a5046` / `#8b918a`, hairline `#ebe9e2`, card `#fff`.
- Type: **Oswald** (700/600, condensed — titles & section headings, UPPERCASE) · **IBM Plex Sans** (400/600 — body) · **IBM Plex Mono** (500/600 — all numbers: quantities, macro values, step numbers). Load/​embed all three. **Note:** Oswald is a *placeholder* for the title face — make it a single config swap; we'll confirm the final card font.
- Radius: card 4px (0 in print), photo 12px, badges full-circle. Footer macro value 23px; title 37px.

## PDF generation
- Provide a way to render one recipe → one A4 PDF. The reference includes `@page { size: A4 }` print rules and a print media block (removes shadow/radius, full-bleed). Browser print-to-PDF should produce a clean page; for batch/server-side generation use headless Puppeteer/Playwright at 794×1123.
- Embed the fonts so output is deterministic.

## Decisions I need you to handle
1. **Overflow / long recipes (important).** The template is a fixed single A4. For recipes whose ingredients or method exceed one page, flow onto a **continuation page**: repeat the header, and show the green macro footer **only on the final page**. (If you think shrink-to-fit is better for our typical lengths, propose it.)
2. **Booklet / meal-plan mode.** The planner often outputs a whole week. Render `<RecipeCard>` **once per recipe** and concatenate into a **single multi-page PDF** (one card per page, continuation pages as needed).
3. **Photo handling.** Pull from Supabase Storage; lazy/placeholder when missing (striped placeholder is in the reference). Respect aspect with `object-fit: cover`.

## Acceptance criteria
- A `<RecipeCard>` that, given the prop contract, reproduces the attached layout at A4.
- Renders to a clean, full-bleed single-page PDF for a normal recipe; continuation page(s) for long ones.
- Macro footer toggles with `showMacros`; missing photo degrades gracefully.
- Booklet mode emits one combined PDF for an array of recipes.
- Macros wired to the engine with the AU-measures + carbs-excludes-fibre rules intact.

## Assets
- Logo: `assets/grams-logo.webp` (transparent; deep-green wordmark + coral underline) — use our canonical brand asset if one exists in the repo.
- Sample photos in `assets/` are for the mock only; production photos come from Supabase Storage.
