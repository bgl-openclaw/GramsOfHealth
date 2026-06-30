-- Aisle on foods, for shopping lists grouped by store section
-- (Produce / Dairy & eggs / Meat & seafood / Bakery / Pantry / Frozen / Drinks).
-- Auto-seeded by name heuristics in a follow-up pass; editable per food in the
-- Foods library; dietitian refines.

alter table foods add column if not exists aisle text;
