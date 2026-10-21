-- 0041_ausnut_source_enum.sql — AUSNUT G1a. DRAFT: apply only on "go G1".
-- The new enum value goes in a migration of its own: Postgres can't use an enum value in the
-- transaction that adds it. Nothing writes source = 'ausnut' until the app can read it (G5);
-- until then AUSNUT-matched and AUSNUT-created foods keep source 'afcd' / 'custom' and carry
-- foods.ausnut_key (added in 0042).
alter type food_source add value if not exists 'ausnut';
