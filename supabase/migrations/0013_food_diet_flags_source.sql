-- Auto/manual distinction on food dietary flags, mirroring recipe_tags.source —
-- lets the dietitian confirm (auto→manual) or dismiss (delete) an auto-seeded
-- flag on a food's Dietary tab, same gesture as recipe diet tags.
alter table food_diet_flags
  add column if not exists source text not null default 'manual'
  check (source in ('manual','auto'));
-- everything seeded so far was heuristic — mark it 'auto' (suggested, to confirm)
update food_diet_flags set source = 'auto';
