# Grams of Health — product brief for a competitor comparison

_Prepared 21 Oct 2026 by Claude Code (which builds and maintains the app's backend and writes the front-end build prompts). Everything below is checked against the live database and the app's code on this date. It's written so another Claude window can compare a competitor's app against it without access to our systems._

---

## How to use this document (for the comparison window)

1. **Part A** is what exists **today**. Part B is what's **in progress or planned**. Part C is decisions, gaps and limits. Part D is a comparison template and what to send back.
2. When comparing, keep three columns separate: **we have it**, **we've planned it**, **we have nothing for it**. Several competitor features may already be on our roadmap with a design. Say so rather than proposing them as new.
3. Respect **our principles** (A2). They're deliberate, not gaps. Example: "AI auto-tags foods" or "AI writes the plan and sends it" conflict with them. Suggest a version that fits (AI drafts, a dietitian approves).
4. Send back the list in **D2's format**, so Claude Code can turn it into build phases directly.

---

# Part A — What exists today

## A1. What the product is

- **Who it's for:** Grams of Health, a dietitian-led practice in Sydney, Australia. It's an **internal staff tool** used by dietitians, interns and admins. There is **no client-facing app yet**.
- **What it does:**
  - keeps a **verified food database** (Australian food composition data plus the practice's own foods);
  - builds a **recipe library** whose nutrition is always calculated from grams;
  - holds **client profiles**: targets, requirements, preferences, structure, check-ins and clinical records;
  - builds **meal plans** for clients, with shopping lists and printable booklets.
- **How it's built** (plain words):
  - one database (Supabase/Postgres, hosted in Sydney), where all rules and access control live;
  - a web app built with Lovable (React);
  - one calculation engine that turns grams into nutrition. The app's copy has been checked against the database on every recipe line.
- **Long-term intent** (owner decisions):
  - run the practice on it first;
  - later a **client app** (phone-first web app, App Store later);
  - later still, **white-label SaaS** for other dietitians.

## A2. Principles (deliberate design choices — treat as fixed)

| Principle | What it means in practice |
|---|---|
| **Every number comes from grams** | Calories, protein, fat, carbs (excluding fibre) and fibre are always calculated live from ingredient grams × per-100 g food data. Nutrition is never typed in or stored on a recipe. |
| **Australian measures** | tsp = 5 mL, tbsp = 20 mL, cup = 250 mL. |
| **No guessing** | If a measure has no real weight (e.g. "1 each" lettuce with no "each" weight), the line is flagged "can't be weighed". The app never invents one. Import placeholders are flagged as "estimated weight" until a person confirms them. |
| **Verified data, human sign-off** | Foods are verified by staff. Recipes earn **AI Verified** automatically only when complete and computable. **Dietitian Verified** is a human sign-off. No machine process ever marks anything verified. |
| **No auto-tagging** | Allergen and diet tags on foods are set by people (owner decision after a failed experiment). Recipes inherit tags from their foods. |
| **Nothing changes silently** | Every food, measure and tag change is logged (who, when, old → new). Changing a verified food's nutrition, density or tags un-verifies it automatically. A Changes inbox shows dietitians what changed. |
| **Published means frozen** | (Being finished now.) A plan sent to a client is a frozen version; later recipe edits never change it. |
| **AI proposes, dietitian decides, engine does the maths** | (Planned AI.) AI output always lands as a draft for a person to accept. AI never sets targets, never marks things verified, and never produces nutrition numbers. |

## A3. Live numbers (21 Oct 2026)

| Area | Today |
|---|---|
| Recipes | 374 (373 with photos) · **26 AI Verified** · 348 Needs review · 0 Dietitian Verified yet |
| Why recipes are in Needs review (recipes affected) | unverified foods ~323 · ingredient lines that can't be weighed ~141 · estimated weights 109 · data-issue notes 21 |
| Foods | 517 (271 from Australian food data, 246 custom) · 311 verified · 15 with a default size · 37 with "Buy as" · protein family set on almost none yet |
| Australian food composition reference rows | 1,588 |
| Unit measures (e.g. "medium = 129 g") | 611 (88 flagged as estimates) |
| Ingredient lines | 3,211 (197 can't be weighed yet) |
| Tags | 12 allergen ("contains"), 5 dietary ("suitable for"), 25 classification (meal type, cuisine…) |
| Recipe variations (saved versions, e.g. "low fat") | 4 · ingredient swap ideas: 25 |
| Clients | 1 real client so far (the client module is newly built) |
| Meal plans | 7, all drafts |
| Staff accounts | 6 (all admins today; roles exist for dietitian, intern, pending) |
| Changes inbox | 56 unreviewed entries |

**Current focus:** the dietitian team is spending about a week verifying foods, the biggest lever for AI Verified recipes.

## A4. Roles and access

| Role | Can do |
|---|---|
| **Admin** | Everything, incl. users and invites |
| **Dietitian** | All clients, targets, clinical records, sign-offs, deleting published plans |
| **Intern** | Only clients ticked for them. Can edit those clients except targets, team access, deleting and clinical records. Sees check-ins only if separately ticked. Never sees clinical records. |
| **Pending** | Signed up but not approved: sees an "awaiting access" screen and none of the client or plan data. Recipe and food data aren't locked down from pending accounts yet; that tightening is planned, see C3. |

Sign-up is **invite-only**. Access is enforced in the database, not just hidden in the app.

## A5. The app, screen by screen

_Taken from the app's code on 21 Oct 2026. Items marked **Gap** look unfinished, placeholder or limited._

### A5.1 Navigation & sign-in
- **Sidebar** (branded "Grams of Health · Recipe studio"):
  - Foods, Recipes, Plans, Clients, Media.
  - Admin group:
    - Quality (all roles);
    - Changes (dietitians/admins), with an orange unreviewed count that refreshes every 60 s;
    - Users (dietitians/admins);
    - Settings (admins).
  - Collapse/expand, signed-in email, Sign out.
  - Below 900 px a compact top bar with a section dropdown replaces the sidebar.
- **Command palette (Ctrl/Cmd+K):** search recipes, foods and plans together and jump to any of them.
- **Sign in:** email and password with a show/hide toggle. "Access is invite-only." **Gap:** no "Forgot password" or reset flow.
- **Accept invitation:**
  - the invite link is checked first (expired links are refused);
  - "You've been invited as {role}", with the email locked;
  - set a password, full name, phone, job title and organisation → Create account.
- **Awaiting access:** pending users see only "Your account is awaiting access" and Sign out.

### A5.2 Recipe library
- **Header and views:** "Showing X of Y recipes"; Table/Grid toggle; **+ New recipe**.
- **Search** by title.
- **Quick filters:** Needs review · AI Verified · Dietitian Verified · Has photo.
- **Filters drawer:**
  - **Nutrition per serve:** two-handle sliders for Calories 0–1200, Protein 0–100 g, Carbs 0–200 g, Fat 0–60 g, Fibre 0–30 g.
  - **Goals computed from macros:**
    - High-protein: ≥25 g/serve.
    - High-fibre: ≥8 g.
    - Low-carb: ≤20 g.
    - Balanced: about 20–35% protein, 35–55% carbs and 25–40% fat.
  - **Clinical goals (by tag):** Heart-healthy, Diabetes-friendly.
  - **Dietary:**
    - "Suitable for" Vegan / Vegetarian / Gluten-free / Dairy-free / Nut-free hides recipes containing a disqualifying ingredient.
    - "Certified label only" also requires the positive diet tag.
    - "Excludes" Egg, Fish, Shellfish, Soy, Sesame, Meat, Honey, High-FODMAP.
  - **Time and servings:** time bands (≤15 / ≤30 / ≤45 / 45+ min) and servings bands (1–2 / 3–4 / 5+).
  - **Status.**
  - **Classification tags by category:** any tag within a category, all selected categories must match.
- **Filter chips, saved views and links:**
  - removable chips for active filters, with Clear all;
  - **Saved views** stored per user (not shared with the team);
  - all filters live in the page link, so a filtered list can be bookmarked or shared.
- **Table view:**
  - columns: Title (photo icon and tag chips), Serves, Time, Kcal/serve, Status, Updated;
  - sortable;
  - engine-suggested tags appear dashed with ✓ confirm / ✕ dismiss;
  - row actions: Duplicate (as a variant), Open print view, Delete.
- **Grid view:** photo cards (the title's first letter when there's no photo), with the same actions.
- **Status pill:** hover shows the reasons, or who signed off and when. AI Verified explains it's "not a dietitian approval".
- **Delete:**
  - lists everything that will be removed, including "Used in N meal plans";
  - you type the recipe title to confirm;
  - **Undo for 15 seconds.**

### A5.3 Recipe editor
- **Top bar:**
  - recipe switcher with search and New recipe;
  - save status (Saving… / All changes saved / Unsaved changes);
  - **Undo/Redo** (50 steps);
  - Duplicate to variant;
  - Download PDF/PNG;
  - Save recipe;
  - Delete (with undo).
- **Header:**
  - hero and second photo slots: upload, remove, or pick from the media library ("Recently used", search, upload);
  - title;
  - **Show macros on export**;
  - serves (−/+), time, "N ingredients · N steps".
- **Verification panel:**
  - status;
  - "What needs fixing (N)";
  - **Sign off as dietitian**: dietitians/admins only, blocked while there are unsaved changes, and if refused a dialog lists why;
  - "Signed off by … · date", with Remove sign-off and an optional note;
  - Data issue box with **Mark data issue resolved**.
- **Tags:**
  - chips inherited from foods: diet tags in green, "Contains X" for allergens;
  - tooltips explain where each tag came from;
  - remove a tag for this recipe only (an override);
  - **+ Add tag**: search, or create one with a category (meal, course, diet, cuisine, other).
- **Profiles (saved recipe versions):**
  - tabs: Base, each profile, **+ New profile** (e.g. "Higher protein");
  - markers: machine draft, verified (green), base changed / needs re-review (amber), orphaned change (red);
  - actions: Rename, Discard draft / Delete profile, "Verified against the current base";
  - edits while a profile is selected are stored as differences from the base.
- **"Make it…" curated swaps:**
  - goal chips, then "Swap to X" for matching ingredients (keeps quantity and unit);
  - when the suggested food is missing from the library: "Add to library…", which opens New food pre-filled;
  - "No curated swap" list;
  - Manage swaps.
  - **Gap:** swaps can be removed in the app but not created.
- **Macro strip** (sticky):
  - Calories, Carbs (excluding fibre), Protein, Fat, Fibre;
  - basis toggle: **Per serve / Recipe total / Per 100 g** (with total weight);
  - **Adjust target**.
- **Adjust target panel:**
  - **Sliders mode:**
    - pick a macro, then set a target with a two-handle slider;
    - a shaded band shows what the recipe can actually reach, and a marker shows the current value;
    - nudge buttons (±10%, ±step);
    - warning when part of the range is unreachable.
  - **Type a request mode:** e.g. "get fibre between 5 and 6", "fat to 12", "add 400 calories".
  - **Preview changes:**
    - result before → after ("within target" / "closest we can get");
    - the other macros before → after;
    - each ingredient's gram change and household-unit change;
    - "N ingredients left alone", with reasons.
  - **Apply to editor** or **Save as profile…**. Nothing is written until applied and saved.
- **Ingredients:**
  - columns: Qty (2 decimals), Size, Food, Prep;
  - **Size** dropdown groups: "Sizes & pieces" (grams shown, "estimate" flagged), "Spoons & cups" (only if they weigh something), "Weight" (g), "No weight";
  - **+ Add a size:** name with suggestion chips, weight in g (or mL when the food has a density), validation;
  - inline warnings: "Can't be weighed … Open food", "Estimated weight … Open food";
  - **Food picker:** search, verified tick, kcal/100 g, plus **Create a new food** inline (name, energy, protein, fat, carbs, fibre, density);
  - **Show contribution:** a per-line value and bar for a chosen macro, plus a total row;
  - + Add ingredient, + Add section heading (e.g. "Marinade").
  - **Gap:** the "drag to reorder" handle doesn't drag; click moves a line up, double-click moves it down.
- **Method:** numbered steps; add and remove. Same reorder gap.
- **Live A4 card preview** (hide/show).
- **Gaps:**
  - no warning when leaving with unsaved changes;
  - removing a photo only saves on Save, while uploading saves immediately.

### A5.4 Recipe export
- **Formats:** Download PDF (multi-page, best quality) or PNG (page 1 only).
- **Print view:** in a new tab, with a Print button.
- **Card layout:**
  - logo, title, "Serves N", minutes, hero photo;
  - ingredients with section headings, fractions (½, ¼, ⅓) and prep notes;
  - numbered directions;
  - optional macro footer per serve;
  - long recipes flow onto "cont. 2/3" pages.
- **Gaps:** the second photo never prints; there's no subtitle field yet.

### A5.5 Foods
- **Foods library:**
  - "Showing X of Y foods", + New food;
  - search by name or ID;
  - quick filters: Verified, Needs review, Missing macros;
  - **Filters drawer:**
    - Source: My library, AFCD, Custom. AFCD alone browses the 1,588 reference foods.
    - Aisle.
    - Contains allergens.
    - Per-100 g sliders.
    - Status: Verified, Needs review, Has density.
  - saved views;
  - table columns: name (with allergen chips), source, kcal/100 g, P, F, C, fibre, aisle, status;
  - after Save & verify you return to the list with that row highlighted.
  - **Gap:** the Grid toggle does nothing.
- **Food page:**
  - **Header:**
    - editable name, Unsaved badge, Verified / Draft badge;
    - **Save draft** and **Save & verify**;
    - source badge (AFCD/Custom), AFCD key;
    - warns before leaving with unsaved edits.
  - **Nutrients per 100 g:**
    - macros: energy, protein, fat, available carbs, fibre, sugars, saturated fat, density;
    - minerals: sodium, potassium, calcium, iron, zinc, magnesium;
    - vitamins: folate, B12;
    - empty optional fields are flagged "needs entry".
    - Note on screen: the extra nutrients are informational and don't affect recipe macros.
  - **Shopping:** aisle; **Buy as** (grams only, or a pack/size such as "can · 400 g").
  - Mark as unverified.
  - **Protein family** (dietitians/admins).
  - **Tags:** "Allergen — contains" and "Dietary — suitable for" toggle chips; recipes inherit them.
  - **Unit conversions:**
    - "Available units" chips (e.g. "1 tbsp = 15 g", estimate flagged);
    - **Default size** ("Recipes that say 'each' use this size");
    - each measure has editable grams, an **estimate** pill with **Confirm**, and delete;
    - add a measure with suggestion chips and "Make this the default size".
  - **Change history** (last 50, reviewed or not).
  - **Delete food** ("Used in N recipes").
- **New custom food:** name, optional ID, macros, density. It can arrive pre-filled from a swap.
- **AFCD entry:** read-only, with **Import to foods**. **Gap:** labels are raw field names.

### A5.6 Media
- **Library:**
  - grid or table; "Showing X of Y";
  - multi-upload and drag-and-drop;
  - uploads are optimised in the browser: HEIC → JPEG, longest edge 2000 px, metadata removed;
  - search by name or folder; **Unused** filter; saved views;
  - "used by N recipes" / unused badge.
- **Menu on each image:**
  - **Rename** (updates the recipes using it);
  - **Replace…** (same link, so recipes keep it);
  - Copy public URL;
  - **Set as hero for…** a recipe;
  - Download;
  - Delete (clears the photo from recipes).
- **Gaps:**
  - the image detail page isn't linked from anywhere;
  - only one folder level, up to 1,000 files a folder;
  - no alt text, tags or captions;
  - all images are public links.

### A5.7 Meal plans
- **Plans list:**
  - search, client filter, saved views;
  - columns: Title (with a **Draft** / **Published · vN** badge and a notes preview), Client, Days, # recipes, Created, Open, delete;
  - deleting warns if the plan has published versions.
  - **Gap:** the list's "New plan" button skips the new-plan form (client, days, start date, title).
- **Plan editor:**
  - **Header:**
    - title, Draft/Published badge, "For {client}";
    - Days and Start date, both locked once published;
    - "Start date needed to publish".
  - **Publish:**
    - the database checks can block it;
    - recipes in Needs review trigger "Publish anyway?";
    - an unavailable recipe version blocks it;
    - publishing freezes a snapshot.
  - **Published banner:** "The client's booklet and shopping list are frozen", with **Start new version**. The editor becomes read-only.
  - **Version history:** date, who, a Needs-review note, plus Booklet and Shopping list links for each version.
  - Notes box.
  - **Weekly average:** Energy/Protein/Carbs/Fat/Fibre bars against the average of the days' targets. Green 90–110%, amber 75–90% or 110–125%, red otherwise.
- **Day cards:**
  - "Mon 26 Oct · Moderate day";
  - a day-type selector (Default/Hard/Moderate/Rest) following the client's weekly pattern, with **Reset to weekly pattern**;
  - "No Hard-day targets set — using Default targets";
  - "1,850 / 2,000 kcal" plus compact bars;
  - **Gap-fill** ("Needs ~450 kcal · 20 g protein" / "Over by ~200 kcal") opens the picker pre-filtered to fit.
- **Meal slots:**
  - the client's own slots (or Breakfast/Lunch/Dinner/Snacks), with a "Free choice" badge;
  - + Add per slot;
  - each recipe row: drag to another slot or day, client screening badge, kcal, **servings in 0.25 steps**, remove.
- **Recipe picker:**
  - search; **Hide blocked** (on by default for client plans);
  - chips: kcal bands, protein / carb / fat / fibre bands, "High protein", "Low-carb", "Balanced", time, servings, every tag category;
  - recipes with variations expand to each version: status (Base / Verified / Not verified / Verification outdated / Machine draft / Unavailable), kcal and P/C/F;
  - picking a blocked or unconfirmed recipe warns with reasons, but still adds it.
- **Client screening badges:** Blocked · reason / Unconfirmed / Disliked.
- **Gaps:**
  - the grid doesn't show which saved version was chosen, and there's no button to switch it;
  - no automatic plan generation;
  - the client's repeat limits, batch cooking and protein spread aren't checked or warned about yet.

### A5.8 Shopping list & booklet
- **Shopping list:**
  - grouped by aisle, with counts;
  - each item: name ("unverified" badge where relevant), **buy hint** ("buy 3 (medium)", "buy 2 × can (400 g each)"), "appears in", total grams;
  - warning for lines that can't be weighed, linking to Quality;
  - published plans show the frozen version, with "View current draft" when one exists;
  - **Export as PDF** (plain text list).
  - **Gap:** no ticking off, manual items, pantry exclusions or quantity editing.
- **Export booklet:**
  - version selector (current draft or a published version); drafts get a **DRAFT** stamp;
  - options: include cover page, append shopping-list page;
  - Download PDF / PNG (page 1), Preview print page.
- **Booklet contents:**
  - **Cover:** title, "For {client} · N recipes · N days", notes, a weekly target adherence table with bars, plan totals, per-day kcal/protein/carbs/fat.
  - One A4 recipe card per plan entry.
  - A shopping-list page.
- **Gaps:**
  - recipe cards show the recipe's own serves and quantities, not the plan's servings;
  - a recipe used several times prints several times;
  - there's no day-by-day meal schedule page;
  - the booklet's shopping page is a single page with no aisles or buy hints;
  - the per-day table leaves out fibre.

### A5.9 Clients
- **Clients list:**
  - search; quick filters Active / Paused / Finished; Has plan; saved views;
  - columns: Name, Status, Dietitian, Primary goal, Latest weight (date), Default kcal, Last check-in, # plans.
- **Client page:** one long page with a sticky section menu (a horizontal strip on mobile). New clients save Identity first.
- **Identity:**
  - name, status, email, phone, date of birth, sex (plus an equation constant for Other/Unspecified), height, activity level (with its multiplier), assigned dietitian, protein g/kg;
  - "Staff notes — never shown to clients";
  - delete (also removes clinical files).
  - **Goals:** active goals with a Primary badge, detail, target date and End goal; past goals listed.
  - **Weight log.**
- **Targets:**
  - cards for Default / Hard / Moderate / Rest: kcal and P · C · F · fibre, the source (Dietitian / Calculator, accepted), who and when, Edit, History (every save kept).
  - **Calculator (Mifflin–St Jeor):**
    - as-of date;
    - BMR, activity factor, TDEE and protein grams, with warnings;
    - full working;
    - links to fix missing inputs;
    - "Use for {day type} → Accept".
  - Only dietitians/admins can edit targets.
- **Requirements:**
  - "Of N recipes: X blocked · Y unconfirmed · Z disliked · W ok";
  - chip groups: **Must avoid** (allergens), **Follows a diet**, **Prefer**;
  - saved immediately.
- **Preferences:**
  - **Food rules:** Avoid ("never") or Dislike ("flagged, not blocked"), optionally "only when a main ingredient (≥10% of weight)", with a note.
  - **Protein likes/dislikes** by family.
  - **Supplements:** dose, timing, notes, start/end, "Show ended".
- **Variety & structure:**
  - cycle length, "don't repeat within N days", "max times per cycle", batch cooking;
  - **weekly day-type pattern** (warns when a day type has no target);
  - **meal slots** (name, kind, time, free choice, order);
  - protein spread per cycle.
  - **Gap:** only the slots and weekly pattern are used by the planner today.
- **Clinical** (dietitians/admins):
  - DEXA / Bloods / Other records: date, summary, key values (name, value, unit);
  - file attachment (PDF/JPEG/PNG/HEIC ≤20 MB), opened through a time-limited link.
- **Check-ins:**
  - date, optional weight (added to the weight log);
  - 1–5 Feeling / Hunger / Energy / Sleep with labelled ends;
  - Bristol 1–7 and bowel notes;
  - training, likes, dislikes, changes wanted, notes;
  - trend bars over the last 8;
  - who entered each;
  - interns only with access.
- **Plans:** new plan (start date defaults to next Monday, days); the client's plans with status and start.
- **Team access:** per intern, "Can see this client" and "Can see check-ins".

### A5.10 Review queues
- **Quality ("Data quality — fix these before exporting plans"):**
  - **Count cards:** recipes with unweighable lines, Atwater mismatches (>3%), import data-issue flags, unconfirmed auto tags, unverified foods.
  - **Needs attention:** one queue ranked by how many recipes each fix unblocks:
    - missing "each" conversions;
    - "Verify X — used in N recipes";
    - machine drafts to review;
    - data issues.
  - **Actions:** each item has one, and some fix in place ("Set default size = medium").
  - **Other lists:** unconfirmed auto tags (confirm/dismiss), lines that don't resolve, Atwater mismatch, ingredients named only in the method, unverified foods.
  - **Gap:** some labels are internal jargon.
- **Changes ("Changes to review"):**
  - every food, measure and tag change, grouped by day;
  - filters: type, "Verification removed only";
  - Open food, Mark reviewed, Mark all reviewed.
  - **Gap:** recipe, plan and client edits aren't logged here, only the food library.

### A5.11 Users & roles
- **Invite:**
  - email and role (intern / dietitian / admin) → an invitation link with an expiry;
  - pending invitations table (copy link, revoke).
  - **Gap:** invitations aren't emailed; the admin copies and sends the link.
- **Team table:** name, email, role (admins can change it), job title, organisation, joined date, delete. Admins and yourself are protected. Dietitians get a read-only view.
- **Gap:** the app shows no role limits on editing foods, recipes or plans. Any staff role can edit the library.

### A5.12 Settings
- Shows the signed-in user only. "More workspace settings will appear here soon."
- **Gap:** tags and categories, diet exclusion rules, protein families, goal types, activity levels and aisles can't be edited in the app.

### A5.13 Integrations
- **AI connector (MCP), read-only:**
  - list recipes, get a recipe (lines and method), search foods (per-100 g macros, verified).
  - **Gap:** no plans or clients, and it may return nothing because the data needs a signed-in user. Untested.
- **PDF:**
  - recipes and booklets are rendered by a third-party HTML-to-PDF service (PDFShift), for signed-in users;
  - if that fails, an image-based PDF is built in the browser;
  - the shopping-list PDF is a separate simple text PDF.
- **Storage:** everything is saved in the database (no browser storage). Undo history and the collapsed sidebar are lost on reload. Saved views are per user.

## A6. End-to-end workflows today

**1. Adding or fixing a food**
1. **Create it.** Search the Australian food composition data and import a row, or create a custom food (per-100 g energy, protein, fat, available carbs, fibre, plus optional sugars, saturated fat, sodium, minerals and vitamins).
2. **Add measures** with grams: sizes (small/medium/large), pieces (clove, slice, can, bunch, head, leaf, handful, cup (grated) …), and a density for liquids so spoons, cups and mL work.
3. **Choose a Default size** (what "each" means, e.g. carrot each = medium 129 g) and a **Buy as** unit for shopping lists.
4. **Tag allergens / suitable-for diets**, set the shopping aisle, and set the protein family (chicken, beef, fish…).
5. **Save draft** or **Save & verify**. Any later change to nutrition, density or tags un-verifies it and lands in the Changes inbox.

**2. Building a recipe**
1. Title, servings, time, photos (media library), sections, ingredient lines (food + quantity + unit + prep note) and method steps.
2. The unit list only offers measures that actually weigh something for that food, with the grams shown. Lines that can't be weighed, or that use an estimated weight, are flagged inline with a link to fix the food.
3. Live macro card (per serve / per 100 g / totals), contribution view and recipe tags inherited from foods.
4. **Adjust to a target:** a solver scales adjustable ingredients (±30%, kitchen-friendly rounding) to hit a protein, energy or fat target, and saves the result as a named **variation** (e.g. "High protein"). The dietitian verifies variations; the system marks them stale when the base recipe changes.
5. **Swaps:** curated ingredient swap suggestions.
6. **Badge:** Needs review (with plain-English reasons) → AI Verified (complete and computable) → Dietitian Verified (signed off by a dietitian; held if the recipe later breaks).
7. **Export:** A4 recipe card (PDF/PNG), with a "show macros on export" switch.

**3. Setting up a client**
1. **Identity:** name, contact, date of birth, sex (with a separate sex for the energy equation when needed), height, activity level, status, assigned dietitian, notes. **Goals** come from an editable list (incl. Performance), with one primary.
2. **Weight log.**
3. **Targets** for four day types (Default / Hard / Moderate / Rest): kcal, protein, carbs, fat, fibre, with full history. A built-in **energy calculator** (Mifflin–St Jeor × activity factor, protein g/kg) shows its full working. Accepting it saves the working with the target.
4. **Requirements:** allergen and diet tags, e.g. Gluten-free, Vegan, Sesame. These block recipes; Heart-healthy-type tags are preferred instead.
5. **Food rules:** avoid (never) or dislike (soft, optionally only when the food is a main ingredient, ≥10% of the recipe's weight).
6. **Protein likes/dislikes** by family, and **supplements**.
7. **Variety & structure:**
   - cycle length;
   - "not again within N days" and "max N per cycle";
   - batch cooking (next-day leftovers allowed);
   - **Mon–Sun day-type pattern**;
   - **own meal slots** (name, kind, time, free choice);
   - protein spread per cycle.
8. **Team access:** which interns see this client, and whether they see check-ins.
9. **Clinical records:** bloods, DEXA and other files with summaries and measurements. Files are private and dietitians only.
10. **Check-ins:**
    - 1–5 scales: feeling, hunger, energy, sleep;
    - Bristol stool scale 1–7;
    - training, likes, dislikes, changes wanted, notes;
    - weight;
    - timeline and trend strip.
11. **Recipe screening for this client:** every recipe is rated **blocked** (contains a blocked tag or avoided food), **unconfirmed** (has unverified ingredients, so allergen tags can't be trusted), **disliked** or **ok**, with reasons. This is used across the library and the planner.

**4. Building and sending a meal plan** (the dates, slots, quarter-serve and publishing parts are being finished now, see B1)
1. **Create a plan** for a client (or an unassigned one), with days and a start date.
2. **Each day knows its date and day type** (from the client's weekly pattern, overridable), and compares against that day's targets with balance bars. Gap-fill opens the recipe picker pre-filtered to fit the remaining calories and protein.
3. **Rows are the client's own meal slots.** Add recipes, or a saved variation, via a picker that shows the client's screening badges. Drag between slots and set servings in quarter steps.
4. **Weekly average** against targets.
5. **Shopping list:** grams by aisle, with "buy N × can / bunch / each".
6. **Booklet export:** cover with adherence to targets, one A4 card per recipe and a shopping page, as a PDF. Cards currently show each recipe as written, not scaled to the plan's servings.
7. **Publish:**
   - warns about any recipe still in Needs review;
   - freezes a version (the booklet and shopping list never change after that);
   - "Start new version" to edit again; version history is kept.

**5. Quality and review**
- **Quality page:** the recipes and foods that need attention, ranked by how many recipes each fix unblocks.
- **Changes inbox:** every food, measure and tag change, for dietitians to review.

---

# Part B — In progress and planned

## B1. In progress (this week)

- **Plans P1** (backend live and tested; front-end prompt with Lovable): dates and day types, the client's own meal slots, quarter serves, and Draft → Published with frozen versions and history.
- **Food verification week** by the dietitians, plus a work list for them: 88 estimated weights to weigh or confirm, and 197 recipe lines that can't be weighed yet. Each row says which measure to add or switch to, never the grams.
- **Recipe units clean-up** (done this week): unit lists only show measures that weigh something, kg is retired, estimated weights are flagged and "Buy as" is in.

## B2. Plans P2 — templates and bulk (planned; for fitness challenges and programs)

- **Template plans,** e.g. "4-Week Fitness Challenge", with **energy bands** such as 1,500 / 1,800 / 2,100 / 2,400 kcal. Portions scale per band using the existing servings and adjustment tools.
- **Groups,** e.g. "October Challenge":
  - assign a template to everyone in one go, each person getting their band or individual scaling to their own targets;
  - **bulk outputs:** a booklet per person or per band and a shopping list per band;
  - delivery later by email or the client app.
- **Template changes:** after a template is edited, a button pushes the new version to everyone or to chosen people (recommended over automatic updates).
- **Open questions:**
  - are participants full clients or a lighter record (name, email, band, allergies)? Lighter, upgradeable, is recommended;
  - how many bands?

## B3. AI roadmap (planned; Claude API via secure server functions)

**Rule:**
- **AI proposes, the dietitian decides, the engine does the maths.**
- Every AI output is a draft, tagged with the model and time, and accepted or rejected by a person.
- AI never sets targets, never marks anything verified, never auto-applies tags and never produces nutrition numbers.

| Phase | Feature | What it does | Client data sent? |
|---|---|---|---|
| AI-0 | Groundwork | Server-side AI calls, a log of every run (tokens, cost), monthly spend guard, feature switches, accuracy tests per feature | — |
| AI-1 | **Food label reader** | Photo of a nutrition panel / supplier spec → draft food (per-100 g values, kJ→kcal, allergen statement → suggested tags for a person to tap). Sanity checks flag per-serve/per-100 g mix-ups and energy mismatches. "Check against label" for existing foods. | No |
| AI-2 | **Recipe import & clean-up** | Paste text / PDF / photo / link → draft recipe matched to *our* foods in Australian measures; unknown foods become "new food needed". Clean-up proposals for messy imported recipes, accepted one by one. | No |
| AI-3 | **Consult transcript → summary & key points** | Upload a transcript (Fireflies, Zoom, Teams, Otter, pasted notes) → consult summary in the practice's template, proposed client-record updates (new dislikes, requirements, supplements, weight, goals) each with its source quote, follow-ups, and flags for clinical judgement. Targets never changed by AI. | Yes (after privacy/consent update) |
| AI-4 | **Clinical document reader** | Blood test / DEXA PDF → table of results (analyte, value, unit, range, flag) to confirm into the client's record; trends over time | Yes |
| AI-5 | **Draft meal plans** | Code supplies only screened recipes and enforces the hard rules (blocked never used, targets within tolerance, repetition, protein spread); AI does judgement (variety, batch cooking, practicality) and writes a one-line reason per day. Lands as a draft plan for the dietitian. | Yes (de-identified profile) |
| Later | Check-in summaries · client-app assistant · Fireflies auto-import | Weekly brief per client before consults; an in-app assistant that answers only from the client's plan and our library and escalates to the dietitian | Yes |

**Order and cost:**
- Order: AI-0 → AI-1 → AI-2 → AI-3 → AI-4 → AI-5.
- Estimated running cost is about **$50–80 a month for ~100 active clients**, plus a one-off ~$15 to work through the food and recipe backlog.
- **Prerequisites:** an Anthropic account and key with a spend limit; updated privacy and consent wording for recordings and overseas AI processing (Australian Privacy Principles).

## B4. Client app (planned; after Foundation)

- **Shape:** a second, phone-first app on the **same database**. Each client signs in and sees only their own things. Clients are invited by their dietitian.
- **What clients see and add:**
  - **See:** published plans, recipes scaled to their servings, shopping list, goals, supplements, and targets *only if the dietitian allows it*. A per-client "show numbers" setting defaults to hidden, e.g. for clients at risk of disordered eating.
  - **Add:** check-ins, weights, progress photos, messages, meal ticks.
  - **Never:** clinical records, staff notes, other clients, drafts, verification status.

| Phase | Clients get |
|---|---|
| P0 | Nothing visible: security tightening first |
| P1 | Sign in, this week's plan, recipes with method and photos, shopping list |
| P2 | Check-ins and weights in the app; dietitian inbox |
| P3 | Messaging and notifications (iPhone home-screen web apps support notifications) |
| P4 | Meal ticks, progress photos, habit goals |
| P5 | Automated check-in reminders and templates; AI check-in summaries and draft plans (dietitian-approved) |
| P6 | App Store version (wrapping the same app), Apple Health / Google Fit, payments if wanted |

- **Rollout:** start as a phone-friendly web app (Add to Home Screen), then wrap it for the App Store later rather than rebuilding.
- **Also planned around it:**
  - check-in automation: reminders, designable check-in templates, dietitian inbox;
  - compliance: consent records, a log of who viewed clinical data, data export and deletion, retention rules.

## B5. Foundation and white-label (planned, parked until the practice is further along)

**The model:** one app and one database serving many practices. Each practice sees only its own data and its own branding.

| Phase | What it does |
|---|---|
| T1 | Organisations table; a platform-owner role; every practice record stamped with its organisation; existing data assigned to Grams of Health |
| T2 | Every access rule rewritten per practice, with leak tests using a fake second practice; shared reference data read-only |
| T3 | Branding from the web address (name, logo, colours); a practice settings page |
| T4 | Onboarding: create a practice and invite its admin; optionally copy a starter library (a licensing lever) |

- **Later:** billing (Stripe, per seat or per active client), custom domains, data processing agreements.
- **Decisions already proposed:**
  - each practice has its own food and recipe library (optionally seeded from Grams of Health's);
  - shared reference data is managed by the platform;
  - one practice per login;
  - no platform access to a practice's data by default.

## B6. Other ideas discussed (not scheduled)

- **Integrations already on the practice's accounts:**
  - GoHighLevel (leads/CRM);
  - Xero (billing);
  - Google Calendar (bookings);
  - Fireflies (consult transcripts);
  - Resend (email);
  - Stripe (subscriptions).
- **Product ideas:**
  - the verified recipe library as its own product or premium tier;
  - pack-size rounding on shopping lists;
  - client share-links for plans;
  - automated nudges.

---

# Part C — Decisions, gaps and honest limits

## C1. Open owner decisions
- **Food page "Save draft":** a recent change means any edit un-verifies the food. The recommended alternative is to un-verify only on calorie-relevant changes. The app may already behave this way after a recent update; to be confirmed.
- **Clients seeing numbers in the client app:** parked. The plan is a per-client switch, default hidden.
- **Plans P2:** whether participants are full clients or lighter records, how many bands, and how template changes reach participants.
- **AI-3 / AI-4:**
  - can interns see consult notes?
  - transcript retention;
  - the summary template headings.

## C2. Known gaps and limits today
- **No client-facing app.** No client logins, messaging, notifications, client self-check-ins or meal ticks yet.
- **No automation yet.** No reminders and no scheduled check-ins.
- **No AI features yet.** The groundwork, verified data and audit trail are in place.
- **The verified pool is small** (26 AI Verified recipes) until foods are verified. Meal-type tags are thin, especially Lunch.
- **Protein families aren't set on real foods yet,** so protein preferences and spread can't work yet.
- **Planning is manual.** No plan generator and no templates or bulk plans yet (P2).
- **Booklets are PDF only.** No emailing to the client from the app yet.
- **Single practice.** No multi-practice or white-label support yet.
- **From the screen inventory (A5):**
  - **Booklets:**
    - recipe cards aren't scaled to plan servings;
    - repeated recipes print repeatedly;
    - no day-by-day schedule page;
    - the booklet's shopping page has no aisles or buy hints.
  - **Shopping list:** no ticking off, manual items or pantry exclusions.
  - **Planner:**
    - the chosen recipe version isn't shown, and there's no button to switch it;
    - the variety rules (repeats, batch cooking, protein spread) are stored but not applied.
  - **Invites and sign-in:** invites aren't emailed, and there's no password reset.
  - **Settings:** an empty placeholder; lookups (tags, diet rules, goal types, activity levels, aisles) can't be edited in the app.
  - **Changes log:** covers foods only, not recipes, plans or clients.
  - **Recipe editor:**
    - curated swaps can't be created in the app, only removed;
    - drag-to-reorder doesn't really drag (click and double-click move lines);
    - no unsaved-changes warning;
    - the second photo never prints.
  - **Media:** no alt text or captions; all images are public links.
  - **PDF:** booklets are rendered by a third-party PDF service (client names on covers leave our systems), with an in-browser fallback.
- **Not mobile-first.** It's a desktop staff web app; the recipe editor does have responsive layouts.
- **Security hardening is pending,** owner says "at the end": recipe and food data aren't yet restricted to staff, plus key rotation, leaked-password protection and staff two-factor sign-in.

## C3. What we consider strengths (worth checking the competitor against)
- **Every number is traceable:** calculated from grams of verified food data, and identical in the database and the app (checked on all 3,211 lines).
- **Explicit verification states** with plain-English reasons, plus human sign-off.
- **A full audit trail and Changes inbox,** where changing a verified food automatically un-verifies it.
- **Per-client recipe screening** (blocked / unconfirmed / disliked / ok) that refuses to trust unverified allergen data.
- **Day-type targets** (hard / moderate / rest) with a built-in calculator that shows its working.
- **Recipe variations** made by a solver, verified by a dietitian, and flagged when the base recipe changes.
- **Published plans are frozen,** with version history.
- **Fine-grained access:** interns per client, check-ins and clinical records separately.

---

# Part D — Comparison template and what to send back

## D1. Suggested comparison table

| Area | Grams of Health today | Planned (where) | Competitor | Gap / opportunity | Fits our principles? |
|---|---|---|---|---|---|
| Food database & verification | | | | | |
| Recipe builder & nutrition | | | | | |
| Recipe variations / adjust to target | | | | | |
| Client profile & targets | | | | | |
| Screening (allergies, diets, dislikes) | | | | | |
| Meal plan building | | | | | |
| Templates / programs / challenges | | B2 | | | |
| Shopping lists | | | | | |
| Booklets / exports / delivery | | | | | |
| Check-ins & progress tracking | | B4 | | | |
| Client app & messaging | | B4 | | | |
| Automation & reminders | | B4 | | | |
| AI features | | B3 | | | |
| Team roles & permissions | | | | | |
| Practice management (bookings, billing, CRM) | | B6 | | | |
| Multi-practice / white-label | | B5 | | | |
| Compliance & privacy | | B4 | | | |
| Pricing / packaging | | | | | |

## D2. What to send back to Claude Code
For each competitor function worth adding, one block:

```text
Function: <name as the competitor calls it>
What it does: <1–3 sentences, from the user's point of view>
Who uses it: dietitian / intern / admin / client
Closest thing we have or have planned: <A5 screen / B-section, or "none">
Why it matters: <time saved, client outcome, revenue, retention…>
Suggested priority: must / should / could
Conflicts with a principle? <which one, and a version that fits>
Notes: <screens, flows, wording worth copying; anything unclear>
```

Then a short summary:
- the **top 5** additions;
- anything the competitor does **worse** that we should keep doing our way;
- any **pricing or packaging** insight relevant to white-label.

---

## Glossary
- **AFCD:** Australian Food Composition Database (FSANZ), the reference nutrition data.
- **AI Verified:** automatic recipe badge meaning complete and computable. Every food is verified, every line has a real weight, and there's a title, photo, ingredients and method.
- **Dietitian Verified:** a human sign-off on an AI Verified recipe.
- **Day type:** Default / Hard / Moderate / Rest. Each can have its own targets, and a client's week follows a Mon–Sun pattern.
- **Default size:** what "1 each" means for a food (e.g. carrot = medium, 129 g).
- **Buy as:** the unit a shopping list counts a food in (e.g. "buy 2 × can").
- **Estimated weight:** an imported measure that was never weighed. Recipes using one stay in Needs review until a person confirms it.
- **Variation:** a saved version of a recipe (e.g. "High protein"), stored as changes from the base recipe.
- **Screening:** the per-client rating of every recipe: blocked / unconfirmed / disliked / ok.
