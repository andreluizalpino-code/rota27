-- ROTA 27 · migração 0001 · schema + RLS · prefixo r27_
-- O projeto já contém o schema base do Flowdash (clients, projects, profiles, trigger handle_new_user…).
-- Nada aqui toca nesses objetos: tudo da ROTA·27 tem prefixo r27_.
-- Padrão SEGURANCA.md: RLS em tudo, anon sem grant, autor escrito pelo banco. Idempotente.

-- ---------- perfis ----------
create table if not exists public.r27_profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  initial      text not null check (char_length(initial) = 1),
  role         text not null default 'membro' check (role in ('admin','membro')),
  created_at   timestamptz not null default now()
);

create or replace function public.r27_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.r27_profiles (id, display_name, initial, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    upper(left(coalesce(new.raw_user_meta_data->>'initial', new.email), 1)),
    case when new.raw_user_meta_data->>'role' = 'admin' then 'admin' else 'membro' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists r27_on_auth_user_created on auth.users;
create trigger r27_on_auth_user_created
  after insert on auth.users
  for each row execute function public.r27_handle_new_user();

-- usuários que já existirem antes desta migração
insert into public.r27_profiles (id, display_name, initial, role)
select u.id,
       coalesce(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
       upper(left(coalesce(u.raw_user_meta_data->>'initial', u.email), 1)),
       case when u.raw_user_meta_data->>'role' = 'admin' then 'admin' else 'membro' end
from auth.users u
on conflict (id) do nothing;

-- ---------- conteúdo (roteiros) ----------
create table if not exists public.r27_content (
  id         text primary key,
  payload    jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.r27_profiles(id)
);

create table if not exists public.r27_content_history (
  id         bigserial primary key,
  content_id text not null,
  payload    jsonb not null,
  saved_at   timestamptz not null default now(),
  saved_by   uuid
);

create or replace function public.r27_content_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    insert into public.r27_content_history (content_id, payload, saved_at, saved_by)
    values (old.id, old.payload, old.updated_at, old.updated_by);
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists r27_content_touch on public.r27_content;
create trigger r27_content_touch before insert or update on public.r27_content
  for each row execute function public.r27_content_touch();

-- ---------- votos / notas / ideias ----------
create table if not exists public.r27_votes (
  user_id    uuid not null references public.r27_profiles(id) on delete cascade,
  route_id   text not null,
  value      boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

create table if not exists public.r27_notes (
  user_id    uuid primary key references public.r27_profiles(id) on delete cascade,
  body       text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.r27_ideas (
  id         bigserial primary key,
  user_id    uuid not null references public.r27_profiles(id) on delete cascade,
  route_id   text not null,
  stop_place text,
  kind       text not null check (kind in ('ideia','custo','hotel','duvida')),
  title      text not null check (char_length(title) between 1 and 120),
  body       text check (body is null or char_length(body) <= 1000),
  link       text check (link is null or link = '' or link ~* '^https?://'),
  amount     numeric(12,2) check (amount is null or amount >= 0),
  currency   text not null default '€',
  created_at timestamptz not null default now()
);

-- autor sempre do banco, nunca do cliente
create or replace function public.r27_stamp_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  if tg_table_name in ('r27_votes','r27_notes') then new.updated_at := now(); end if;
  return new;
end $$;

drop trigger if exists r27_votes_stamp on public.r27_votes;
create trigger r27_votes_stamp before insert or update on public.r27_votes for each row execute function public.r27_stamp_user();
drop trigger if exists r27_notes_stamp on public.r27_notes;
create trigger r27_notes_stamp before insert or update on public.r27_notes for each row execute function public.r27_stamp_user();
drop trigger if exists r27_ideas_stamp on public.r27_ideas;
create trigger r27_ideas_stamp before insert on public.r27_ideas for each row execute function public.r27_stamp_user();

-- ---------- RLS ----------
alter table public.r27_profiles        enable row level security;
alter table public.r27_content         enable row level security;
alter table public.r27_content_history enable row level security;
alter table public.r27_votes           enable row level security;
alter table public.r27_notes           enable row level security;
alter table public.r27_ideas           enable row level security;

-- segunda tranca: anon sem grant nas tabelas r27_
revoke all on public.r27_profiles, public.r27_content, public.r27_content_history,
              public.r27_votes, public.r27_notes, public.r27_ideas from anon;
grant select, insert, update, delete on public.r27_votes, public.r27_notes, public.r27_ideas to authenticated;
grant select on public.r27_profiles, public.r27_content, public.r27_content_history to authenticated;
grant insert, update on public.r27_content to authenticated;
grant usage, select on sequence public.r27_ideas_id_seq, public.r27_content_history_id_seq to authenticated;

create or replace function public.r27_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.r27_profiles where id = auth.uid() and role = 'admin');
$$;

drop policy if exists r27_profiles_read on public.r27_profiles;
create policy r27_profiles_read on public.r27_profiles for select to authenticated using (true);

drop policy if exists r27_content_read on public.r27_content;
create policy r27_content_read on public.r27_content for select to authenticated using (true);
drop policy if exists r27_content_write on public.r27_content;
create policy r27_content_write on public.r27_content for all to authenticated using (public.r27_is_admin()) with check (public.r27_is_admin());

drop policy if exists r27_history_read on public.r27_content_history;
create policy r27_history_read on public.r27_content_history for select to authenticated using (public.r27_is_admin());

drop policy if exists r27_votes_read on public.r27_votes;
create policy r27_votes_read on public.r27_votes for select to authenticated using (true);
drop policy if exists r27_votes_own on public.r27_votes;
create policy r27_votes_own on public.r27_votes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists r27_notes_read on public.r27_notes;
create policy r27_notes_read on public.r27_notes for select to authenticated using (true);
drop policy if exists r27_notes_own on public.r27_notes;
create policy r27_notes_own on public.r27_notes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists r27_ideas_read on public.r27_ideas;
create policy r27_ideas_read on public.r27_ideas for select to authenticated using (true);
drop policy if exists r27_ideas_insert on public.r27_ideas;
create policy r27_ideas_insert on public.r27_ideas for insert to authenticated with check (user_id = auth.uid());
drop policy if exists r27_ideas_delete on public.r27_ideas;
create policy r27_ideas_delete on public.r27_ideas for delete to authenticated using (user_id = auth.uid() or public.r27_is_admin());

-- ---------- realtime ----------
do $$ begin alter publication supabase_realtime add table public.r27_votes; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.r27_notes; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.r27_ideas; exception when duplicate_object then null; end $$;
