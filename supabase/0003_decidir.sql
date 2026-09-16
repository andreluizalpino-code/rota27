-- ROTA 27 · aba Decidir: ordem de preferência (arrastar) + corações por critério
-- Rodar no SQL Editor. Idempotente. O coração antigo (r27_votes) fica, sem uso.

create table if not exists public.r27_ranking (
  user_id    uuid not null references public.r27_profiles(id) on delete cascade,
  route_id   text not null,
  pos        int  not null check (pos >= 1),
  updated_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

create table if not exists public.r27_hearts (
  user_id    uuid not null references public.r27_profiles(id) on delete cascade,
  route_id   text not null,
  crit       text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, route_id, crit)
);

-- autor e hora sempre do banco
create or replace function public.r27_stamp_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  if tg_table_name in ('r27_votes','r27_notes','r27_ranking','r27_hearts') then new.updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists r27_ranking_stamp on public.r27_ranking;
create trigger r27_ranking_stamp before insert or update on public.r27_ranking for each row execute function public.r27_stamp_user();
drop trigger if exists r27_hearts_stamp on public.r27_hearts;
create trigger r27_hearts_stamp before insert or update on public.r27_hearts for each row execute function public.r27_stamp_user();

alter table public.r27_ranking enable row level security;
alter table public.r27_hearts  enable row level security;
revoke all on public.r27_ranking, public.r27_hearts from anon;
grant select, insert, update, delete on public.r27_ranking, public.r27_hearts to authenticated;

drop policy if exists r27_ranking_read on public.r27_ranking;
create policy r27_ranking_read on public.r27_ranking for select to authenticated using (true);
drop policy if exists r27_ranking_own on public.r27_ranking;
create policy r27_ranking_own on public.r27_ranking for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists r27_hearts_read on public.r27_hearts;
create policy r27_hearts_read on public.r27_hearts for select to authenticated using (true);
drop policy if exists r27_hearts_own on public.r27_hearts;
create policy r27_hearts_own on public.r27_hearts for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

do $$ begin alter publication supabase_realtime add table public.r27_ranking; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.r27_hearts; exception when duplicate_object then null; end $$;

select 'ok' as decidir, (select count(*) from public.r27_profiles) as pessoas;
