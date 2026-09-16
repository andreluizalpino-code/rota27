-- ROTA 27 · função de "ping" para o keepalive (GitHub Actions a cada 3 dias)
-- Devolve só a hora do servidor; não expõe dado nenhum. Anon pode chamar.
create or replace function public.r27_ping()
returns timestamptz
language sql
stable
as $$ select now(); $$;
grant execute on function public.r27_ping() to anon, authenticated;
select public.r27_ping() as ok;
