-- Ten per-100g nutrient fields on foods (display + dietitian entry — NOT used
-- by the recalculation engine, which reads only the five macros), plus the
-- seven nutrients afcd_master doesn't yet carry so AFCD-sourced foods can be
-- backfilled by afcd_key. Values load from seed/afcd_master_full.csv
-- (scripts/gen-nutrients-sql.ts). All nullable; custom foods stay null for the
-- dietitian to fill from the product label. Idempotent.

-- afcd_master: the seven nutrients not already present
-- (satfat g, sugars g, sodium_mg are already columns, loaded at import).
alter table afcd_master add column if not exists potassium_mg   numeric;
alter table afcd_master add column if not exists calcium_mg     numeric;
alter table afcd_master add column if not exists iron_mg        numeric;
alter table afcd_master add column if not exists zinc_mg        numeric;
alter table afcd_master add column if not exists magnesium_mg   numeric;
alter table afcd_master add column if not exists folate_ug      numeric;  -- Total folates
alter table afcd_master add column if not exists vitamin_b12_ug numeric;

comment on column afcd_master.potassium_mg   is 'Potassium (K) per 100 g, mg — AFCD "Potassium (K) (mg)"';
comment on column afcd_master.calcium_mg     is 'Calcium (Ca) per 100 g, mg — AFCD "Calcium (Ca) (mg)"';
comment on column afcd_master.iron_mg        is 'Iron (Fe) per 100 g, mg — AFCD "Iron (Fe) (mg)"';
comment on column afcd_master.zinc_mg        is 'Zinc (Zn) per 100 g, mg — AFCD "Zinc (Zn) (mg)"';
comment on column afcd_master.magnesium_mg   is 'Magnesium (Mg) per 100 g, mg — AFCD "Magnesium (Mg) (mg)"';
comment on column afcd_master.folate_ug      is 'Total folates per 100 g, µg — AFCD "Total folates (ug)" (DFE also available in source if preferred)';
comment on column afcd_master.vitamin_b12_ug is 'Vitamin B12 per 100 g, µg — AFCD "Cobalamin (B12) (ug)"';

-- foods: the ten nutrient fields, per 100 g
alter table foods add column if not exists sugars_100g      numeric;
alter table foods add column if not exists satfat_100g      numeric;
alter table foods add column if not exists sodium_100g      numeric;
alter table foods add column if not exists potassium_100g   numeric;
alter table foods add column if not exists calcium_100g     numeric;
alter table foods add column if not exists iron_100g        numeric;
alter table foods add column if not exists zinc_100g        numeric;
alter table foods add column if not exists magnesium_100g   numeric;
alter table foods add column if not exists folate_100g      numeric;
alter table foods add column if not exists vitamin_b12_100g numeric;

comment on column foods.sugars_100g      is 'Total sugars per 100 g, g';
comment on column foods.satfat_100g      is 'Saturated fat per 100 g, g';
comment on column foods.sodium_100g      is 'Sodium per 100 g, mg';
comment on column foods.potassium_100g   is 'Potassium per 100 g, mg';
comment on column foods.calcium_100g     is 'Calcium per 100 g, mg';
comment on column foods.iron_100g        is 'Iron per 100 g, mg';
comment on column foods.zinc_100g        is 'Zinc per 100 g, mg';
comment on column foods.magnesium_100g   is 'Magnesium per 100 g, mg';
comment on column foods.folate_100g      is 'Total folates per 100 g, µg';
comment on column foods.vitamin_b12_100g is 'Vitamin B12 per 100 g, µg';
