-- ============================================================
-- Alexandria Burger — Checklist Operacional
-- Schema do banco (referência do estado final)
--
-- Histórico de aplicação neste projeto (nesta ordem):
--   1. supabase_schema.sql                     (este arquivo, versão original)
--   2. supabase_schema_update_roles.sql        (2 papéis -> 3 papéis)
--   3. supabase_schema_add_setor.sql           (restrição por setor)
--   4. supabase_schema_fotos_e_unidades.sql    (fotos via Storage + rename Lisboa)
-- Se for recriar o projeto do zero, pode rodar só este arquivo —
-- ele já reflete o resultado final dos 4 scripts (exceto o bucket de
-- storage, que precisa ser criado à parte via supabase_schema_fotos_e_unidades.sql).
-- ============================================================

-- 1) PERFIS (vinculado a auth.users)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  role text not null check (role in ('colaborador','franqueado','franqueadora')),
  unidade text, -- obrigatório para colaborador/franqueado; null para franqueadora
  setor text check (setor is null or setor in ('gerente','cozinha','salao','bar','caixa')),
  -- setor = null -> acesso a todos os setores da unidade (franqueado/franqueadora)
  -- setor = 'cozinha' | 'salao' | 'bar' | 'caixa' | 'gerente' -> colaborador vê só aquele setor
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- funções auxiliares (security definer evita recursão de RLS)
create or replace function public.current_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_unidade()
returns text language sql stable security definer set search_path = public as $$
  select unidade from public.profiles where id = auth.uid()
$$;

create or replace function public.current_setor()
returns text language sql stable security definer set search_path = public as $$
  select setor from public.profiles where id = auth.uid()
$$;

create policy "profiles_select" on public.profiles for select
using ( id = auth.uid() or public.current_role() = 'franqueadora' );

create policy "profiles_update_own" on public.profiles for update
using ( id = auth.uid() ) with check ( id = auth.uid() );

-- ============================================================
-- 2) SUBMISSÕES — um checklist = 1 unidade + 1 data + 1 turno
create table public.checklist_submissions (
  id uuid primary key default gen_random_uuid(),
  unidade text not null,
  data date not null,
  turno text not null,
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  unique (unidade, data, turno)
);

alter table public.checklist_submissions enable row level security;

create policy "submissions_select" on public.checklist_submissions for select
using ( public.current_role() = 'franqueadora' or unidade = public.current_unidade() );

create policy "submissions_insert" on public.checklist_submissions for insert
with check ( unidade = public.current_unidade() );

create policy "submissions_update" on public.checklist_submissions for update
using ( unidade = public.current_unidade() )
with check ( unidade = public.current_unidade() );

-- ============================================================
-- 3) ITENS — estado de cada item do checklist dentro de uma submissão
create table public.checklist_items (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.checklist_submissions(id) on delete cascade,
  item_key text not null, -- ex: "cozinha_0_3" (prefixo antes do "_" = setor)
  done boolean not null default false,
  foto boolean not null default false,
  foto_url text, -- URL pública da foto no bucket "checklist-fotos"
  valor text default '',
  obs text default '',
  updated_at timestamptz not null default now(),
  unique (submission_id, item_key)
);

alter table public.checklist_items enable row level security;

create policy "items_select" on public.checklist_items for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
);

create policy "items_write" on public.checklist_items for all
using (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
)
with check (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or split_part(item_key,'_',1) = public.current_setor() )
);

-- ============================================================
-- 4) RESPONSÁVEIS — responsável + horário por setor dentro de uma submissão
create table public.checklist_responsaveis (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.checklist_submissions(id) on delete cascade,
  setor text not null,
  responsavel text default '',
  horario time,
  unique (submission_id, setor)
);

alter table public.checklist_responsaveis enable row level security;

create policy "resp_select" on public.checklist_responsaveis for select
using (
  exists (
    select 1 from public.checklist_submissions s
    where s.id = submission_id
      and ( public.current_role() = 'franqueadora' or s.unidade = public.current_unidade() )
  )
  and ( public.current_setor() is null or setor = public.current_setor() )
);

create policy "resp_write" on public.checklist_responsaveis for all
using (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or setor = public.current_setor() )
)
with check (
  exists ( select 1 from public.checklist_submissions s where s.id = submission_id and s.unidade = public.current_unidade() )
  and ( public.current_setor() is null or setor = public.current_setor() )
);

-- ============================================================
-- 5) STORAGE — bucket público para as fotos tiradas pela câmera
insert into storage.buckets (id, name, public)
values ('checklist-fotos', 'checklist-fotos', true)
on conflict (id) do nothing;

create policy "checklist_fotos_read" on storage.objects for select
using ( bucket_id = 'checklist-fotos' );

create policy "checklist_fotos_insert" on storage.objects for insert
with check (
  bucket_id = 'checklist-fotos'
  and exists (
    select 1 from public.checklist_submissions s
    where s.id::text = (storage.foldername(name))[1]
      and s.unidade = public.current_unidade()
  )
);

create policy "checklist_fotos_update" on storage.objects for update
using (
  bucket_id = 'checklist-fotos'
  and exists (
    select 1 from public.checklist_submissions s
    where s.id::text = (storage.foldername(name))[1]
      and s.unidade = public.current_unidade()
  )
);

-- ============================================================
-- 6) EXEMPLO — como cadastrar cada pessoa depois de criar o login em
-- Authentication > Users > Add user (copie o UUID gerado e cole abaixo).
-- Rode uma linha destas por pessoa, ajustando os valores:
--
-- insert into public.profiles (id, nome, role, unidade, setor) values
--   ('COLE-O-UUID-AQUI', 'Nome da franqueadora', 'franqueadora', null, null);
--
-- insert into public.profiles (id, nome, role, unidade, setor) values
--   ('COLE-O-UUID-AQUI', 'Nome do dono da unidade', 'franqueado', 'Araucária', null);
--
-- insert into public.profiles (id, nome, role, unidade, setor) values
--   ('COLE-O-UUID-AQUI', 'Nome do colaborador', 'colaborador', 'Araucária', null);
--
-- insert into public.profiles (id, nome, role, unidade, setor) values
--   ('COLE-O-UUID-AQUI', 'Nome do colaborador da cozinha', 'colaborador', 'Araucária', 'cozinha');
