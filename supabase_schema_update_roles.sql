-- ============================================================
-- Ajuste: 2 papéis -> 3 papéis
-- colaborador (equipe da unidade) / franqueado (dono da unidade) / franqueadora (rede toda)
-- Rodar uma vez, depois do supabase_schema.sql original
-- ============================================================

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('colaborador','franqueado','franqueadora'));

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select
using ( id = auth.uid() or public.current_role() = 'franqueadora' );

drop policy if exists "submissions_select" on public.checklist_submissions;
create policy "submissions_select" on public.checklist_submissions for select
using ( public.current_role() = 'franqueadora' or unidade = public.current_unidade() );

drop policy if exists "items_select" on public.checklist_items;
create policy "items_select" on public.checklist_items for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
);

drop policy if exists "resp_select" on public.checklist_responsaveis;
create policy "resp_select" on public.checklist_responsaveis for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
);
