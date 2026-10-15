-- tests/sql/food_default_size.test.sql — live test of migration 0025.
-- One DO block that always ends by raising, so everything rolls back.
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Uses carrot (sizes small 74 / medium 129 / large 169, no "each" row at time of writing).
do $$
declare g numeric; d text; n int; n0 int; log text := '';
begin
  select count(*) into n0 from line_priceability where food_id='carrot' and unit='each' and not priced;
  -- T1 setting a default materialises "each"
  update foods set default_size='medium' where food_id='carrot';
  select grams into g from unit_conversions where food_id='carrot' and unit='each';
  select count(*) into n from line_priceability where food_id='carrot' and unit='each' and not priced;
  if g is distinct from (select grams from unit_conversions where food_id='carrot' and unit='medium') or n <> 0 then
    raise exception 'FAIL T1 each=% blocked=%', g, n; end if;
  log := format('T1 default=medium → each=%sg, carrot each lines blocked %s→%s', g, n0, n);
  -- T2 editing the default size's grams flows to "each"
  update unit_conversions set grams=130 where food_id='carrot' and unit='medium';
  select grams into g from unit_conversions where food_id='carrot' and unit='each';
  if g <> 130 then raise exception 'FAIL T2 each=%', g; end if;
  log := log || ' | T2 medium→130 → each=130';
  -- T3 hand-editing "each" clears the default and keeps the typed value
  update unit_conversions set grams=140 where food_id='carrot' and unit='each';
  select default_size into d from foods where food_id='carrot';
  select grams into g from unit_conversions where food_id='carrot' and unit='each';
  if d is not null or g <> 140 then raise exception 'FAIL T3 default=% each=%', d, g; end if;
  log := log || ' | T3 hand-edit each=140 → default cleared, 140 kept';
  -- T4 switching default re-syncs; deleting the default size row clears the default, keeps "each"
  update foods set default_size='large' where food_id='carrot';
  select grams into g from unit_conversions where food_id='carrot' and unit='each';
  if g <> (select grams from unit_conversions where food_id='carrot' and unit='large') then raise exception 'FAIL T4a each=%', g; end if;
  delete from unit_conversions where food_id='carrot' and unit='large';
  select default_size into d from foods where food_id='carrot';
  if d is not null or not exists (select 1 from unit_conversions where food_id='carrot' and unit='each') then
    raise exception 'FAIL T4b default=%', d; end if;
  log := log || format(' | T4 switch to large → each=%s; delete large → default cleared, each kept', g);
  -- T5/T6 validation
  begin update foods set default_size='huge' where food_id='carrot'; raise exception 'FAIL T5';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | T5 unknown size refused'; end;
  begin update foods set default_size='each' where food_id='carrot'; raise exception 'FAIL T6';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | T6 "each" refused'; end;
  raise exception 'ALL PASS (rolled back): %', log;
end $$;
