# Grams of Health recipe tool — build roadmap

An internal tool for Nikki's dietitian team to store, analyse and build recipe cards. Macros are computed from the Australian Food Composition Database, recalculated live as a dietitian edits, and exported as an A4 PDF or PNG identical to the current Canva card.

## Decided stack

- **Database and backend: Supabase** (Postgres). It also provides image Storage and team Auth for later phases.
- **Recalculation engine: a portable TypeScript module.** Runs client-side for instant live totals; shared by every screen. Ported from the working Python engine in the seed.
- **Front-end: Lovable** (React), designed in **Claude Design**, which hands off directly to Lovable.
- **Data preparation: Cowork**, which parses the 750 recipes and matches them to the AFCD master.
- **Working assets** (the seed CSVs and the AFCD master) live in your Dropbox folder and are imported into Supabase. Dropbox holds the editable source files; Supabase holds the live data.

Why Supabase: one database from seed to production with no SQLite-to-Postgres migration, native to Lovable so the Claude Design to Lovable to Supabase pipeline is one chain, and it supplies the login and image storage the tool needs. Images sit in Supabase Storage and each recipe row stores the URL.

## Tool ownership

- **Claude Code** — Supabase schema, data import, the engine, the tests. The backend brain.
- **Claude Design and Lovable** — the editor, the library screen and the A4 card, wired to Supabase.
- **Cowork** — the foods and recipe matching for the 750, against the AFCD master.

## Phases

**Phase 0 — Backend foundation (Claude Code).** Repo, Supabase schema (six tables), and import of the AFCD master, the seed foods, the unit conversions and the two recipes. Deliverable: a populated Supabase database.

**Phase 1 — Recalculation engine (Claude Code).** Port the Python engine to TypeScript and test that it reproduces the seed numbers, 369 and 226 kcal per serve with Atwater within one percent. Deliverable: trusted, tested maths the front-end can import.

**Phase 2 — Recipe editor (Design then Lovable).** Four-field ingredient lines linked to the library, live totals and per-serve figures, the selectable per-ingredient macro-contribution column, create-a-size and create-a-food that save and become reusable, method steps, header fields, the show-on-export tick, and duplicate-to-variant. Deliverable: a dietitian builds a recipe and watches the macros move.

**Phase 3 — A4 card and export (Design then Lovable).** The fixed A4 template that doubles as the editor's live preview, exporting to PDF and PNG, with the hardcoded logo, the optional five-figure macro footer including fibre, and images from Supabase Storage. Deliverable: a published card identical to today's.

**Phase 4 — Library and ingest.** Browse, search and verify the foods and conversions; import Cowork's full recipes file; and surface the outlier report: lines that fail to resolve to grams, ingredients named only in the method like the salmon case, and energy mismatches. Deliverable: the 750 loaded and checkable.

**Phase 5 — Login and go live.** Supabase Auth scoped to Nikki's team, then deploy.

## Sequence note

Phases 0 and 1 run on the seed alone, so the data and the maths are proven before any screen exists. Claude Design then designs against the real schema, Lovable wires it to Supabase, and Cowork's 750 plug into phase 4. Nothing waits on the front-end.
