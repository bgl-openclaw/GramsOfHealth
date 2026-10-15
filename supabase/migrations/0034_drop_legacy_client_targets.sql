-- 0034_drop_legacy_client_targets.sql  (Clients roadmap C5 — owner go 2026-10-15)
-- The app now reads targets from client_targets / client_current_targets and
-- restrictions from client_requirements (+ client_recipe_screen). Verified before
-- dropping: the only client's old values equalled its current Default target;
-- restrictions were empty; no views/functions depended on these columns; no app
-- code reads them (C4a search + every later diff reviewed).
-- Snapshot: seed/archive/clients_legacy_targets_snapshot.csv (ids + values, no names).
alter table clients drop column if exists kcal_target;
alter table clients drop column if exists protein_target_g;
alter table clients drop column if exists carb_target_g;
alter table clients drop column if exists fat_target_g;
alter table clients drop column if exists fibre_target_g;
alter table clients drop column if exists restrictions;
