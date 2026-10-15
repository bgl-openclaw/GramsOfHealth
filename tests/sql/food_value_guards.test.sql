-- tests/sql/food_value_guards.test.sql — live test of migration 0035 (always rolls back).
do $$
declare log text := '';
begin
  begin update foods set density_g_ml = -1 where food_id = 'honey'; raise exception 'FAIL G1';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := 'G1 negative density refused'; end;
  begin update foods set density_g_ml = 0 where food_id = 'honey'; raise exception 'FAIL G2';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | G2 zero density refused'; end;
  update foods set density_g_ml = null where food_id = 'honey';
  log := log || ' | G3 blank density accepted';
  begin update foods set protein_100g = -0.1 where food_id = 'honey'; raise exception 'FAIL G4';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | G4 negative protein refused'; end;
  begin insert into unit_conversions (food_id, unit, grams) values ('honey', 'zz', 0); raise exception 'FAIL G5';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | G5 zero-gram conversion refused'; end;
  raise exception 'ALL PASS (rolled back): %', log;
end $$;
