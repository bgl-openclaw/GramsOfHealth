-- Food changes propagate into recipes; food deletion removes ONLY that
-- ingredient line from each recipe that uses it. The recipe row, its other
-- lines, sections, steps and images are untouched; macros and derived tags
-- recompute automatically because both are computed at read time.
-- ON UPDATE CASCADE keeps lines linked if a food_id is ever renamed.
alter table ingredient_lines
  drop constraint if exists ingredient_lines_food_id_fkey;
alter table ingredient_lines
  add constraint ingredient_lines_food_id_fkey
  foreign key (food_id) references foods (food_id)
  on update cascade on delete cascade;
