-- 0054_document_intake_fixes.sql — fixes found reviewing Lovable's document intake (D1), 22 Oct 2026.
-- APPLIED live 22 Oct 2026 (apply_migration "0054_document_intake_fixes"); document_intake_0054 passed in the dry run.
--  1. The clinical-records bucket accepts Word documents and text transcripts (.docx, .txt, .vtt, .srt), as well as
--     PDFs and photos. Before, uploading them failed with "mime type not supported".
--  2. A found item that repeats one already found in the same document (same section, field and value) is skipped
--     quietly instead of being added again — so "Read again" and a second AI pass don't duplicate items or bring back
--     conflicts someone has already settled.
-- Test: tests/sql/document_intake_0054.test.sql

update storage.buckets
   set allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/heif',
                                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                  'text/plain', 'text/vtt', 'application/x-subrip']
 where id = 'clinical-records';

create or replace function client_document_facts_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_text text;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- migrations, the owner
  if tg_op = 'INSERT' then
    -- the same item already found in this document: skip it (jsonb equality ignores key order)
    if exists (select 1 from client_document_facts x
                where x.record_id = new.record_id and x.section = new.section and x.field = new.field and x.value = new.value) then
      return null;
    end if;
    new.client_id := (select client_id from client_clinical_records where id = new.record_id);
    new.created_by := auth.uid();
    new.status := 'pending';
    new.target_table := null; new.target_id := null; new.existing_value := null; new.applied_at := null;
    new.decided_by := null; new.decided_by_name := null; new.decided_at := null;
    if new.method = 'ai' then new.certainty := 'check'; end if;
    if new.quote <> '' then
      select document_text into v_text from client_clinical_records where id = new.record_id;
      if v_text is null or position(doc_text_norm(new.quote) in doc_text_norm(v_text)) = 0 then
        raise exception 'That quote isn''t in the document, so the item can''t be added.';
      end if;
    end if;
    return new;
  end if;
  if coalesce(current_setting('goh.facts', true), '') <> 'on' then
    raise exception 'Found items are filed with apply_document_facts or decide_document_fact.';
  end if;
  return new;
end $$;
revoke execute on function client_document_facts_guard() from public, anon, authenticated;
