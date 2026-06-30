# Lovable build checklist — Grams of Health

Run these **in order**, each as a **separate Lovable message**; let one finish before
pasting the next. The backend (Supabase) for every step already exists.

**Design:** the whole app uses the v2 design system in `docs/design-system.md` (deeper `brand-green #003018` + coral accent, the browse/filter/tag/status patterns). **Step 0 — run the global design-system prompt (design-system.md §4a) first** so every screen inherits the palette/type/shape. Attach `design_v2/.../Recipes Browser.dc.html` + `Recipe Editor.dc.html` to Lovable for pixel fidelity. The reusable browse layout + tag accept/dismiss + status pill (§4b, §4c) apply to Recipes, Foods, Media, Clients, Plans — fold them into the steps below.

**Standing rules (apply to every step):**
- Do NOT change `src/lib/engine.ts` or the Supabase schema.
- All tables/RPCs below ALREADY EXIST in our external Supabase — do NOT create
  tables or run migrations (`supabase db push` won't touch our project; you only
  have the anon key). Build app code only.
- Keep auth. Every macro/number comes from the engine (grams-first), never a
  stored value.

---

## 1. Shell + Recipes library + routes  *(foundation — do first)*
```text
Add a persistent collapsible left-sidebar app shell (Recipes, Foods, Media, Plans, Users, Quality + user menu with sign-out), brand look (#f4f3ef/#fff/#e6e4de, green #2f7a4d, IBM Plex). Put all app routes behind the existing auth guard.
- Migrate the editor from ?recipe=<id> to /recipes/$id (keep all current editor behaviour). / redirects to /recipes.
- /recipes = library. Default table view (title, servings, time, kcal/serve, verified %, last edited) with a card/grid toggle (thumbnail from image_url_1), search, and filters. Rows open /recipes/$id. "New recipe" → createRecipe() → /recipes/$id. Duplicate-to-variant per row.
- Compute kcal/serve + verified% client-side efficiently: load all foods + unit_conversions + ingredient_lines ONCE, run the engine per recipe (don't query per row).
- Add /recipes/$id/print: a full-bleed A4 card only (no shell) reusing the A4 card component; set @page { size: A4; margin: 0 }. This is the export + booklet capture target.
```

## 2. Tags + filters  *(needs step 1)*
```text
Build filtering + tagging for the Recipes library and meal-plan recipe picker. Tables exist: tags(id,label,category), recipe_tags(recipe_id,tag_id,source).

DERIVED FILTERS (computed live via the engine — no DB writes):
- Calories/serve: 100-cal buckets — <200, 200–299, 300–399, 400–499, 500–599, 600–699, 700+ (multi-select chips) + optional min/max range.
- Protein/serve buckets (+ "High protein ≥25 g"); Carbs "Low-carb ≤20 g"; Fat buckets; Fibre "High fibre ≥8 g".
- Time ≤15/≤30/≤45/45+; Servings 1–2/3–4/5+; Macro profile chips (High-protein, Low-carb, Balanced, High-fibre); Status chips (Verified, Needs review, Has photo).
- Compute by loading foods + unit_conversions + ingredient_lines once; thresholds in one editable config.

TAGS:
- Filter chips grouped by category (meal, course, cuisine, diet), multi-select; OR within a category, AND across categories; combine with derived filters + text search.
- Show a recipe's tags on its row/card. source='auto' tags render as "suggested" (muted/dashed); source='manual' solid.
- Data layer: load each recipe's tags (label, category, source); listTags() grouped by category; addRecipeTag(recipe_id, tag_id) [manual]; confirmTag(recipe_id, tag_id) [set source='manual']; removeRecipeTag(recipe_id, tag_id); createTag(label, category).
- Recipe editor: tag editor (add existing/searchable by category, create new, remove) + one-click "confirm" on each suggested tag.
- Meal-plan picker: expose the same calorie-bucket + macro + tag filters.
```

## 3. Foods / ingredients library (+ AFCD)  *(needs step 1)*
```text
Add the Foods library.
- /foods: one search box over two sources via a filter (Mine | AFCD | Unverified). Mine/Unverified read foods; AFCD reads afcd_master (1,588 rows) with server-side ilike search + limit (use listAfcd). Columns: name, source, kcal/100g, protein/fat/carb/fibre, verified.
- /foods/$id: edit per-100g values, a verified toggle (writes foods.verified), and manage that food's unit conversions (list/add/edit/delete rows in unit_conversions; name + grams).
- /foods/new: create a custom food (source 'custom', verified false).
- /afcd/$key: read-only AFCD row + "Import to foods" → clone mapping afcd_master energy_kcal→energy_kcal_100g, protein→protein_100g, fat→fat_100g, carb_avail→carb_avail_100g, fibre→fibre_100g, density via specific_gravity, source='afcd', afcd_key=public_food_key, verified=false.
- Surface verified state as a badge in the editor's food picker and on /recipes cards (any unverified ingredient → recipe "needs review" chip).
```

## 4. Per-food unit exclusions  *(needs step 3 — extends /foods/$id)*
```text
On a food's Unit conversions tab, let the dietitian hide any unit for that food — custom rows AND built-ins (tsp/tbsp/cup/mL). g and kg are the base units and are never hideable. Table food_unit_exclusions(food_id, unit) already exists (authenticated RLS) — do NOT create it.
- Data layer: listExclusionsForFood(food_id), listAllExclusions(), addUnitExclusion(food_id, unit), removeUnitExclusion(food_id, unit).
- Engine (src/lib/engine.ts): add optional exclusions param to toGrams/sizeOptionsFor/macrosForLine/computeRecipe (default []). toGrams returns 0 for an excluded unit (never for g/kg). sizeOptionsFor filters excluded units but always keeps the line's currentUnit so a saved line still renders.
- Foods detail: each unit pill except g/kg gets an × (→ addUnitExclusion); hidden units move to a muted "Hidden" row with Undo (→ removeUnitExclusion). Toast feedback.
- WARN before hiding a unit that recipe lines currently use (those lines will compute 0 g until changed).
- Thread exclusions through everywhere toGrams/sizeOptionsFor are called: recipe editor, plan detail, and /print routes.
```

## 4b. Food-driven dietary suitability  *(needs step 3; used by 2 + 7)*
```text
Dietary suitability is FOOD-DRIVEN. Table food_diet_flags(food_id, flag) exists — flags: meat, fish, shellfish, dairy, egg, gluten, tree_nut, peanut, soy, sesame, honey, high_fodmap. Do NOT create it. A recipe's suitability is COMPUTED from its ingredients (not stored); editing a food's flags must reflect on every recipe + plan that uses it.

FOODS — add a "Dietary" section on /foods/$id: checkboxes "Contains: meat / fish / shellfish / dairy / egg / gluten / tree nuts / peanuts / soy / sesame / honey" + "High-FODMAP". Data: listFoodDietFlags(food_id) → string[]; setFoodDietFlags(food_id, flags[]). Auto-seeded already; the dietitian confirms them while verifying the food.

COMPUTE (engine/app helper): a recipe SATISFIES a restriction when NO ingredient food has any of its blocking flags:
- Vegetarian → meat, fish, shellfish | Vegan → meat, fish, shellfish, dairy, egg, honey | Pescatarian → meat
- Gluten-free → gluten | Dairy-free → dairy | Egg-free → egg | Nut-free → tree_nut, peanut
- Shellfish-free → shellfish | Fish-free → fish | Soy-free → soy | Sesame-free → sesame | Low-FODMAP → high_fodmap
Diabetes-friendly and Heart-healthy are NOT ingredient-derivable — keep as manually-assigned recipe tags (recipe satisfies only if it carries the tag).

USE EVERYWHERE:
- Recipes library "diet" filter → computed from flags (not old diet recipe_tags) + the two clinical tags.
- Meal planner: when the plan's client has restrictions, the recipe picker EXCLUDES (or clearly flags) recipes failing ANY of the client's restrictions, computed from flags (+ clinical tags), with a "why" hint.
- Client restrictions list = the 14: Vegetarian, Vegan, Pescatarian, Gluten-free, Dairy-free, Egg-free, Nut-free, Shellfish-free, Fish-free, Soy-free, Sesame-free, Low-FODMAP, Diabetes-friendly, Heart-healthy.
- Suitability reflects current food data (unverified foods may under-report allergens) — surface that caveat subtly near allergen exclusions.
```

## 5. Media library + editor picker  *(needs step 1)*
```text
Add the Media library on the recipe-images Storage bucket (exists, public).
- /media: grid of all images via supabase.storage.from('recipe-images').list(), filename search, newest-first, drag-and-drop upload. "Unused" filter = objects not referenced by any recipes.image_url_1/2.
- /media/$path: large preview, "Used by" (recipes whose image_url_1/2 = this public URL, linking to /recipes/$id), Replace, Delete, "Set as hero for…" (recipe picker → image_url_1).
- Editor image slots: keep "Upload", ADD "Choose from library" → a media picker DIALOG (same grid + search) that sets image_url_1/image_url_2 without navigating away. Share one uploadRecipeImage helper.
```

## 6. Users, roles & invite-only auth  *(needs step 1)*
```text
Add invite-only auth, profiles, and a Users tab. Backend exists: profiles(id,email,full_name,phone,job_title,organisation,role), invitations(id,email,role,token,expires_at,accepted_at), RPC get_invitation(p_token uuid), is_admin(), and delete_user(target_id). Do NOT create tables or run migrations.

LOGGED-OUT = SIGN IN ONLY: /login shows ONLY email+password sign in. Remove the "Sign up" toggle/link entirely.

REGISTRATION at /register?token=<uuid>: call supabase.rpc('get_invitation', { p_token: token }). If valid=false/no row → "This invitation is invalid or expired — ask your admin" and no form. If valid → form: email (read-only, prefilled), password, full_name (required), phone, job_title, organisation → supabase.auth.signUp({ email, password, options: { data: { full_name, phone, job_title, organisation } } }). The DB trigger creates the profile with the invited role. Don't let the user pick a role.

CURRENT USER: after login load the signed-in profile (select from profiles where id = auth.uid()) into context; expose role. If role = 'pending', show "Your account is awaiting access — contact your admin" instead of the app.

USERS TAB (/users, visible to dietitian + admin): view-only table of profiles (full_name, email, role badge, job_title, organisation, joined). listProfiles() → select * from profiles. ADMIN-ONLY controls (current role === 'admin'):
- "Invite user" → dialog (email + role: dietitian/admin) → insert into invitations → show link `${origin}/register?token=${token}` with Copy.
- Pending invitations list (email, role, expiry) with copy-link + revoke (delete invitation).
- Per-row role control (pending/dietitian/admin).
- Delete user: deleteUser(userId) → supabase.rpc('delete_user', { target_id: userId }), surface error.message as a toast. Show the delete action ONLY for admins; hide it for any row where role='admin' and for the current user's own row. Confirm dialog before deleting.
No emails sent — invites are share-by-link.
```

## 7. Clients + Meal planner  *(needs steps 1–3)*

### 7a — Clients (roster + targets)
```text
Add a Clients area (sidebar "Clients"). Table clients(id, full_name, email, phone, kcal_target, protein_target_g, carb_target_g, fat_target_g, fibre_target_g, restrictions text[], notes) already exists (authenticated RLS) — don't create it.
- /clients list (name, targets summary, # plans); /clients/new; /clients/$id: edit full_name, contact, the five targets (kcal/day + protein/carb/fat/fibre g/day), restrictions (multi-select from the diet tags), notes.
- Data layer: listClients(), getClient(id), saveClient(client), deleteClient(id).
- Restrictions are diet-tag labels used to warn in the planner.
```

### 7b — Meal planner (week grid, balance bars, smart shopping list)
```text
Build the meal planner. Tables exist: meal_plans(id,title,notes,days,created_at,client_id), meal_plan_items(id,meal_plan_id,recipe_id,position,servings_override,day,meal_slot). Don't change the engine; every number comes from it (grams-first).
- /plans list, /plans/new (pick a client + days), /plans/$id editor.
- WEEK GRID: rows = days (1..plan.days); within each day, meal-slot sections (Breakfast, Lunch, Dinner, Snacks). Add recipes per slot via the recipe picker with the tag + 100-cal + macro filters; drag to move/reorder; per-item servings_override; remove.
- BALANCE BARS (the key view): per day, a stacked %-of-target bar for energy + protein + carb + fat (+ fibre) = engine day total ÷ client target. Colour-band 90–110% on-target green, else amber/red. Also one weekly-average bar (week total ÷ target×days) — the weekly average matters more than any single day. No client/targets → show absolute totals instead of %.
- GAP-FILL: per day, show the remaining target ("needs ~450 kcal / 30 g protein") and a "Suggest" action that opens the picker pre-filtered to recipes that fit the gap.
- RESTRICTION WARNING: adding a recipe that conflicts with the client's restrictions (recipe lacks the matching diet tag) shows an inline warning (don't block).
- /plans/$id/shopping: aggregate grams by food_id across the plan (toGrams scaled by servings_override/recipe.servings), GROUPED BY foods.aisle (Produce / Dairy & eggs / Meat & seafood / Bakery / Pantry / Frozen / Drinks). Each row: food · total grams (+ household hint if a unit_conversion exists) · "appears in: …". Unresolved lines → warning banner linking to /quality. Aisle is editable per food on /foods/$id.
- /plans/$id/print: booklet — each plan recipe's A4 card one-per-page (reuse /recipes/$id/print; card wrapper break-after: page; @page A4 margin 0); cover page (plan title, client, weekly target adherence); optional appended shopping-list page. No chrome.
```

## 8. PDF export via the renderer  *(deploy pdf-renderer first; needs steps 1 & 7)*
```text
Route PDF export through our self-hosted Puppeteer renderer instead of html2canvas. Keep client-side PNG for quick single-card shares; all PDF goes through the renderer.
- Add config RENDERER_URL (the deployed pdf-renderer base URL).
- Export action (recipe editor + plan editor): get supabase.auth.getSession() → { access_token, refresh_token }, POST `${RENDERER_URL}/render` with { type: 'recipe'|'plan', id, filename: <title-slug>, access_token, refresh_token }. Response is a PDF blob → download (filename from title). Spinner while rendering; error toast on failure.
- Keep the existing html2canvas path only for "Export PNG" of a single card.
```

## 9. Quality dashboard + command palette  *(needs steps 1–3)*
```text
Add /quality, a data-quality dashboard. Sections, each linking to the relevant /recipes/$id or /foods/$id:
- recipes with lines that don't resolve to grams (engine: toGrams returns 0),
- Atwater mismatch (engine per-serve energy vs 4·P+4·C+9·F+2·fibre differs >~3%),
- "ingredient named only in the method" — READ recipes.data_issue (populated by the Cowork ingest; not derivable in-app),
- count of unverified foods, and recipes with unconfirmed (source='auto') tags.
Add a global ⌘K command palette to jump to any recipe, food, or plan by name.
```
