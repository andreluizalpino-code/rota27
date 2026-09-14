#!/usr/bin/env node
// Gera supabase/seed-content.sql a partir de data/routes.js + data/guia.js (para colar no SQL Editor).
import { readFile, writeFile } from 'node:fs/promises';
import vm from 'node:vm';
const here = new URL('.', import.meta.url);
const evalWindow = async (rel) => { const ctx = { window: {} }; vm.runInNewContext(await readFile(new URL(rel, here), 'utf8'), ctx); return ctx.window; };
const payload = (await evalWindow('../data/routes.js')).ROTA27;
payload.guia = (await evalWindow('../data/guia.js')).ROTA27_GUIA;
const json = JSON.stringify(payload);
if (json.includes('$r27$')) throw new Error('payload contém o delimitador $r27$');
const sql = `-- ROTA 27 · semeadura do conteúdo + guia (gerado em ${new Date().toISOString().slice(0, 10)})
-- Rodar no SQL Editor. Idempotente: atualiza se já existir (versão anterior vai para r27_content_history).
insert into public.r27_content (id, payload)
values ('rota27', $r27$${json}$r27$::jsonb)
on conflict (id) do update set payload = excluded.payload;
select id, jsonb_array_length(payload->'routes') as rotas, (select count(*) from jsonb_object_keys(payload->'guia')) as bases_com_guia, updated_at from public.r27_content where id = 'rota27';
`;
await writeFile(new URL('seed-content.sql', here), sql);
console.log(`seed-content.sql · ${(sql.length / 1024).toFixed(1)} KB · ${payload.routes.length} rotas · ${Object.keys(payload.guia).length} bases com guia`);
