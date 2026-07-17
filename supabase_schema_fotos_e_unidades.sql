-- ============================================================
-- Ajuste: fotos reais (câmera + Supabase Storage) + renomeação
-- da unidade de Lisboa (Portugal) -> Lisboa (PT)
-- ============================================================

-- 1) Coluna para guardar a URL da foto
alter table public.checklist_items add column if not exists foto_url text;

-- 2) Bucket de armazenamento das fotos (público para leitura)
insert into storage.buckets (id, name, public)
values ('checklist-fotos', 'checklist-fotos', true)
on conflict (id) do nothing;

drop policy if exists "checklist_fotos_read" on storage.objects;
create policy "checklist_fotos_read" on storage.objects for select
using ( bucket_id = 'checklist-fotos' );

drop policy if exists "checklist_fotos_insert" on storage.objects;
create policy "checklist_fotos_insert" on storage.objects for insert
with check (
  bucket_id = 'checklist-fotos'
  and exists (
    select 1 from public.checklist_submissions s
    where s.id::text = (storage.foldername(name))[1]
      and s.unidade = public.current_unidade()
  )
);

drop policy if exists "checklist_fotos_update" on storage.objects;
create policy "checklist_fotos_update" on storage.objects for update
using (
  bucket_id = 'checklist-fotos'
  and exists (
    select 1 from public.checklist_submissions s
    where s.id::text = (storage.foldername(name))[1]
      and s.unidade = public.current_unidade()
  )
);

-- 3) Renomeia a unidade dos perfis de teste de Lisboa (Portugal) -> Lisboa (PT)
-- (a lista de unidades do app mudou; rode isso só se você tiver cadastrado
-- perfis com unidade = 'Lisboa (Portugal)')
update public.profiles set unidade = 'Lisboa (PT)' where unidade = 'Lisboa (Portugal)';
