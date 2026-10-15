-- 0033_meal_slot_name_required.sql
-- A meal slot must have a name: save_client_structure trims names, and the C4b
-- form can submit an empty one. Refuse it (the whole structure save rolls back
-- and the app shows the database message). No existing rows are affected.
alter table client_meal_slots drop constraint if exists client_meal_slots_name_required;
alter table client_meal_slots add constraint client_meal_slots_name_required check (btrim(name) <> '');
