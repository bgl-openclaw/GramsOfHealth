-- 0039c_my_details_clients_only.sql — found in code review of Lovable P1a (6c858f4f).
-- The app decides "is this a client?" by calling my_details() and treating a refusal
-- as "not a client". 0039 answered staff and pending accounts with { linked: false }
-- instead of refusing, so after publishing, STAFF would have been routed into the
-- client area. my_details() now refuses any account whose role isn't 'client'
-- ({ ok: false, message: 'Client accounts only.' }); an unlinked CLIENT account still
-- gets { linked: false } (the "connecting your account" screen). Only the first
-- lines of the function change. Idempotent.
create or replace function my_details() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  c clients%rowtype;
  v_num boolean;
  v_diet record;
  v_contact text;
begin
  if coalesce(current_staff_role(), '') <> 'client' then
    return jsonb_build_object('ok', false, 'message', 'Client accounts only.');
  end if;
  v_id := my_client_id();
  if v_id is null then
    return jsonb_build_object('linked', false,
      'practice_name', app_setting('practice_name'), 'practice_email', app_setting('practice_email'));
  end if;
  select * into c from clients where id = v_id;
  v_num := c.numbers_allowed and c.client_shows_numbers;
  select full_name, email into v_diet from profiles where id = c.assigned_dietitian;
  v_contact := case when app_setting('client_contact') = 'dietitian'
                    then coalesce(nullif(btrim(v_diet.email), ''), app_setting('practice_email'))
                    else app_setting('practice_email') end;
  return jsonb_build_object(
    'linked', true,
    'full_name', c.full_name,
    'first_name', split_part(btrim(c.full_name), ' ', 1),
    'practice_name', app_setting('practice_name'),
    'practice_email', app_setting('practice_email'),
    'contact_email', v_contact,
    'dietitian_name', v_diet.full_name,
    'primary_goal', (select jsonb_build_object('label', gt.label, 'detail', g.detail, 'target_date', g.target_date)
                     from client_goals g join goal_types gt on gt.key = g.goal_type
                     where g.client_id = v_id and g.is_primary and g.ended_on is null limit 1),
    'requirements', coalesce((select jsonb_agg(jsonb_build_object('label', t.label,
                       'kind', case when t.kind = 'allergen' then 'avoid'
                                    when exists (select 1 from tag_blockers b where b.tag_id = t.id) then 'diet'
                                    else 'prefer' end) order by t.label)
                     from client_requirements r join tags t on t.id = r.tag_id where r.client_id = v_id), '[]'::jsonb),
    'foods_to_avoid', coalesce((select jsonb_agg(f.display_name order by f.display_name)
                       from client_food_rules fr join foods f on f.food_id = fr.food_id
                       where fr.client_id = v_id and fr.rule = 'avoid'), '[]'::jsonb),
    'foods_disliked', coalesce((select jsonb_agg(f.display_name order by f.display_name)
                       from client_food_rules fr join foods f on f.food_id = fr.food_id
                       where fr.client_id = v_id and fr.rule = 'dislike'), '[]'::jsonb),
    'supplements', coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'dose', s.dose, 'timing', s.timing)
                       order by s.position, s.name)
                     from client_supplements s
                     where s.client_id = v_id
                       and (s.ended_on is null or s.ended_on >= (now() at time zone app_setting('timezone'))::date)), '[]'::jsonb),
    'numbers_allowed', c.numbers_allowed,
    'show_numbers', v_num,
    'targets', case when v_num then (
        select jsonb_agg(jsonb_build_object('day_type', t.day_type, 'kcal', t.kcal, 'protein_g', t.protein_g,
                 'carb_g', t.carb_g, 'fat_g', t.fat_g, 'fibre_g', t.fibre_g)
                 order by array_position(array['default','hard','moderate','rest'], t.day_type))
        from client_current_targets t where t.client_id = v_id) end);
end $$;
