-- ROTA 27 · migração 0001 · schema + RLS
-- Padrão SEGURANCA.md (Flowdash): RLS em tudo, anon sem grant, autor escrito pelo banco.
-- Rodar no SQL Editor do projeto ROTA·27. Idempotente.

create extension if not exists pgcrypto;

-- ---------- perfis ----------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  initial      text not null check (char_length(initial) = 1),
  role         text not null default 'membro' check (role in ('admin','membro')),
  created_at   timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, initial, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    upper(left(coalesce(new.raw_user_meta_data->>'initial', new.email), 1)),
    coalesce(new.raw_user_meta_data->>'role', 'membro')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- conteúdo (roteiros) ----------
create table if not exists public.content (
  id         text primary key,
  payload    jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table if not exists public.content_history (
  id         bigserial primary key,
  content_id text not null,
  payload    jsonb not null,
  saved_at   timestamptz not null default now(),
  saved_by   uuid
);

create or replace function public.content_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    insert into public.content_history (content_id, payload, saved_at, saved_by)
    values (old.id, old.payload, old.updated_at, old.updated_by);
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists content_touch on public.content;
create trigger content_touch before insert or update on public.content
  for each row execute function public.content_touch();

-- ---------- votos / notas / ideias ----------
create table if not exists public.votes (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  route_id   text not null,
  value      boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

create table if not exists public.notes (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  body       text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.ideas (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  route_id   text not null,
  stop_place text,
  kind       text not null check (kind in ('ideia','custo','hotel','duvida')),
  title      text not null check (char_length(title) between 1 and 120),
  body       text check (char_length(body) <= 1000),
  link       text check (link is null or link ~* '^https?://'),
  amount     numeric(12,2) check (amount is null or amount >= 0),
  currency   text not null default '€',
  created_at timestamptz not null default now()
);

-- autor sempre do banco, nunca do cliente
create or replace function public.stamp_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  if tg_table_name in ('votes','notes') then new.updated_at := now(); end if;
  return new;
end $$;

drop trigger if exists votes_stamp on public.votes;
create trigger votes_stamp before insert or update on public.votes for each row execute function public.stamp_user();
drop trigger if exists notes_stamp on public.notes;
create trigger notes_stamp before insert or update on public.notes for each row execute function public.stamp_user();
drop trigger if exists ideas_stamp on public.ideas;
create trigger ideas_stamp before insert on public.ideas for each row execute function public.stamp_user();

-- ---------- RLS ----------
alter table public.profiles        enable row level security;
alter table public.content         enable row level security;
alter table public.content_history enable row level security;
alter table public.votes           enable row level security;
alter table public.notes           enable row level security;
alter table public.ideas           enable row level security;

-- segunda tranca: anon sem grant de tabela
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on public.votes, public.notes, public.ideas to authenticated;
grant select on public.profiles, public.content, public.content_history to authenticated;
grant insert, update on public.content to authenticated;
grant usage, select on all sequences in schema public to authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);

drop policy if exists content_read on public.content;
create policy content_read on public.content for select to authenticated using (true);
drop policy if exists content_write on public.content;
create policy content_write on public.content for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists history_read on public.content_history;
create policy history_read on public.content_history for select to authenticated using (public.is_admin());

drop policy if exists votes_read on public.votes;
create policy votes_read on public.votes for select to authenticated using (true);
drop policy if exists votes_own on public.votes;
create policy votes_own on public.votes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists notes_read on public.notes;
create policy notes_read on public.notes for select to authenticated using (true);
drop policy if exists notes_own on public.notes;
create policy notes_own on public.notes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists ideas_read on public.ideas;
create policy ideas_read on public.ideas for select to authenticated using (true);
drop policy if exists ideas_insert on public.ideas;
create policy ideas_insert on public.ideas for insert to authenticated with check (user_id = auth.uid());
drop policy if exists ideas_own on public.ideas;
create policy ideas_own on public.ideas for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------- realtime ----------
do $$ begin
  alter publication supabase_realtime add table public.votes;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.notes;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.ideas;
exception when duplicate_object then null; end $$;
