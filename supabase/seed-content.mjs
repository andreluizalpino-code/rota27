#!/usr/bin/env node
// Semeia/atualiza o conteúdo (data/routes.js) na tabela content do Supabase.
// Uso:  node supabase/seed-content.mjs
// Lê URL + anon de data/config.js; pede e-mail e senha do admin no terminal (nada fica em histórico).
import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import vm from 'node:vm';

const here = new URL('.', import.meta.url);
const evalWindow = async (rel) => {
  const src = await readFile(new URL(rel, here), 'utf8');
  const ctx = { window: {} };
  vm.runInNewContext(src, ctx);
  return ctx.window;
};
const cfg = (await evalWindow('../data/config.js')).ROTA27_CONFIG;
const payload = (await evalWindow('../data/routes.js')).ROTA27;
payload.guia = (await evalWindow('../data/guia.js')).ROTA27_GUIA;
if (!cfg?.supabase?.url || !cfg?.supabase?.anonKey) { console.error('Preencha data/config.js (url + anonKey).'); process.exit(1); }

const rl = createInterface({ input: stdin, output: stdout });
const email = (await rl.question('E-mail do admin: ')).trim();
stdout.write('Senha: ');
const password = await new Promise((res) => {
  let s = ''; stdin.setRawMode(true); stdin.resume(); stdin.setEncoding('utf8');
  const on = (ch) => { if (ch === '\r' || ch === '\n') { stdin.setRawMode(false); stdin.off('data', on); stdout.write('\n'); res(s); } else if (ch === '') process.exit(1); else if (ch === '') s = s.slice(0, -1); else s += ch; };
  stdin.on('data', on);
});
rl.close();

const H = { apikey: cfg.supabase.anonKey, 'Content-Type': 'application/json' };
const auth = await fetch(`${cfg.supabase.url}/auth/v1/token?grant_type=password`, { method: 'POST', headers: H, body: JSON.stringify({ email, password }) });
if (!auth.ok) { console.error('Login falhou.'); process.exit(1); }
const { access_token } = await auth.json();

const res = await fetch(`${cfg.supabase.url}/rest/v1/r27_content?on_conflict=id`, {
  method: 'POST',
  headers: { ...H, Authorization: `Bearer ${access_token}`, Prefer: 'resolution=merge-duplicates,return=minimal' },
  body: JSON.stringify({ id: 'rota27', payload })
});
if (!res.ok) { console.error('Falha ao gravar:', res.status, await res.text()); process.exit(1); }
console.log(`OK · r27_content/rota27 atualizado (${payload.routes.length} rotas, ${Object.keys(payload.places).length} lugares).`);
