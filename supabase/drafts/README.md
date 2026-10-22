# Draft migrations (not applied to production)

These are written and dry-run against the live database (rolled back), but **not applied**. They live outside `supabase/migrations/` on purpose: the Supabase GitHub integration applies every file in `supabase/migrations/` to preview branches, and to production too if "Deploy to production" is on.

| File | Waiting on |
|---|---|
| `0041_ausnut_source_enum.sql`, `0042_ausnut_reference_ai_verified.sql`, `0043_ausnut_apply.sql` | AUSNUT dietitian review (G1 onward) |
| `0046_recipe_meal_types.sql` | Planner set-up review, meal types part |

To apply one, run it through the Supabase MCP `apply_migration` (as the live migrations were), run its test in `tests/sql/`, then move the file into `supabase/migrations/` in the same commit.

"Deploy to production" in the Supabase GitHub integration is **off** (owner, 22 Oct 2026), so merging to `main` never changes the live database. Live changes go through `apply_migration` only.

Note: production records migrations under timestamp versions (e.g. `20261021114316`), while files here are numbered `0001…`. Line the two up (rename the files to production's versions, or record the old ones in production's history) before anything is deployed from Git.
