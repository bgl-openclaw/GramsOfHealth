-- 0029_client_energy_inputs.sql  (Clients roadmap C2 — calculator inputs)
--
-- Gathers one client's Mifflin-St Jeor inputs as of a date: the most recent
-- weight on or before that date (with its date), height, date of birth, sex,
-- the dietitian's equation-sex choice, activity level + factor, protein g/kg.
-- Deliberately does NOT compute anything or decide what is "missing" — the
-- single implementation of the formula and the missing-input rules is
-- packages/energy (copied verbatim into Lovable). Feed the row to
-- energyInputsFromRow() → estimateEnergy().
-- SECURITY INVOKER: callers only get clients their RLS allows.
-- Idempotent.

create or replace function client_energy_inputs(p_client_id uuid, p_as_of date default current_date)
returns table (
  client_id uuid, as_of date,
  weight_kg numeric, weighed_on date,
  height_cm numeric, date_of_birth date,
  sex text, equation_sex text,
  activity_key text, activity_label text, activity_factor numeric,
  protein_g_per_kg numeric)
language sql stable security invoker set search_path = public as $$
  select c.id, p_as_of,
         w.weight_kg, w.recorded_on,
         c.height_cm, c.date_of_birth,
         c.sex, c.equation_sex,
         al.key, al.label, al.factor,
         c.protein_g_per_kg
  from clients c
  left join activity_levels al on al.key = c.activity_level
  left join lateral (
    select cw.weight_kg, cw.recorded_on
    from client_weights cw
    where cw.client_id = c.id and cw.recorded_on <= p_as_of
    order by cw.recorded_on desc, cw.created_at desc
    limit 1
  ) w on true
  where c.id = p_client_id;
$$;

revoke execute on function client_energy_inputs(uuid, date) from public, anon;
grant execute on function client_energy_inputs(uuid, date) to authenticated;
