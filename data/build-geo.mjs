#!/usr/bin/env node
// Gera data/geo.js: traçado real por estrada (OSRM) para os trechos de carro, ônibus e trem de todas as rotas.
// Uso: node data/build-geo.mjs   (só busca pares que ainda não existem; apague data/geo.js para refazer tudo)
import { readFile, writeFile } from 'node:fs/promises';
import vm from 'node:vm';
const here = new URL('.', import.meta.url);
const evalWindow = async (rel) => { const ctx = { window: {} }; try { vm.runInNewContext(await readFile(new URL(rel, here), 'utf8'), ctx); } catch { } return ctx.window; };
const D = (await evalWindow('routes.js')).ROTA27, P = D.places;
const geo = (await evalWindow('geo.js')).ROTA27_GEO || {};
const LAND = new Set(['car', 'bus', 'train']);
const pairs = new Map();
D.routes.forEach(r => r.legs.forEach(L => { if (LAND.has(L.mode) && P[L.from] && P[L.to]) pairs.set(`${L.from}>${L.to}`, L); }));
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
// simplificação Douglas-Peucker em graus (0.004° ≈ 400 m) — suficiente para o zoom regional
const dp = (pts, tol) => {
  if (pts.length < 3) return pts;
  const [a, b] = [pts[0], pts[pts.length - 1]]; let idx = 0, max = 0;
  for (let i = 1; i < pts.length - 1; i++) { const [x, y] = pts[i]; const d = Math.abs((b[0] - a[0]) * (a[1] - y) - (a[0] - x) * (b[1] - a[1])) / Math.hypot(b[0] - a[0], b[1] - a[1]); if (d > max) { max = d; idx = i; } }
  return max > tol ? [...dp(pts.slice(0, idx + 1), tol).slice(0, -1), ...dp(pts.slice(idx), tol)] : [a, b];
};
let n = 0;
for (const [key, L] of pairs) {
  if (geo[key]) continue;
  const a = P[L.from], b = P[L.to];
  const url = `https://router.project-osrm.org/route/v1/driving/${a.lng},${a.lat};${b.lng},${b.lat}?overview=full&geometries=geojson`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': 'rota27-build-geo' } }); const j = await res.json();
    if (j.code !== 'Ok') { console.warn('sem rota', key, j.code); continue; }
    const r = j.routes[0], c = dp(r.geometry.coordinates, 0.004).map(([x, y]) => [+x.toFixed(4), +y.toFixed(4)]);
    geo[key] = { c, km: Math.round(r.distance / 1000), min: Math.round(r.duration / 60) };
    console.log(`${key.padEnd(22)} ${String(geo[key].km).padStart(4)} km  ${String(geo[key].min).padStart(4)} min  ${c.length} pts  (conteúdo: ${L.min} min)`);
    n++; await sleep(400);
  } catch (e) { console.warn('falhou', key, e.message); }
}
await writeFile(new URL('geo.js', here), `// ROTA 27 · traçado por estrada (OSRM/OpenStreetMap) — gerado por data/build-geo.mjs\nwindow.ROTA27_GEO = ${JSON.stringify(geo)};\n`);
console.log(`geo.js · ${pairs.size} pares · ${n} novos`);
