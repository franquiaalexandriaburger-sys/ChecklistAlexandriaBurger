-- ============================================================
-- Ajuste: restrição por setor (ex: colaborador só vê a Cozinha)
-- Rodar uma vez, depois do supabase_schema.sql e do
-- supabase_schema_update_roles.sql
-- ============================================================

alter table public.profiles add column if not exists setor text;
alter table public.profiles drop constraint if exists profiles_setor_check;
alter table public.profiles add constraint profiles_setor_check
  check (setor is null or setor in ('gerente','cozinha','salao','bar','caixa'));
-- setor = null -> acesso a todos os setores da unidade (franqueado/franqueadora)
-- setor = 'cozinha' | 'salao' | 'bar' | 'caixa' | 'gerente' -> colaborador vê só aquele setor

create or replace function public.current_setor()
returns text language sql stable security definer set search_path = public as $$
  select setor from public.profiles where id = auth.uid()
$$;

drop policy if exists "items_select" on public.checklist_items;
create policy "items_select" on public.checklist_items for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
);

drop policy if exists "items_write" on public.checklist_items;
create policy "items_write" on public.checklist_items for all
using (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
)
with check (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
);

drop policy if exists "resp_select" on public.checklist_responsaveis;
create policy "resp_select" on public.checklist_responsaveis for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
  and ( public.current_setor() is null or setor = public.current_setor() )
);

drop policy if exists "resp_write" on public.checklist_responsaveis;
create policy "resp_write" on public.checklist_responsaveis for all
using (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or setor = public.current_setor() )
)
with check (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or setor = public.current_setor() )
);
