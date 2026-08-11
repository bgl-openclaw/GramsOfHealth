-- Adjustment-engine roles on foods (backend-only; never rendered in UI).
-- Six engine roles; NULL = unclassified/junk → the engine never moves it.
alter table foods add column if not exists role text
  check (role in ('adjustable_protein','adjustable_carb','adjustable_fat',
                  'bulk_veg','flavour_base','structural'));
comment on column foods.role is 'Adjustment engine role. NULL = frozen (unclassified or junk). Backend-only.';
