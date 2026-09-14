// ROTA 27 · configuração pública (vai para o repositório)
// backend: "local"    → usa data/routes.js (arquivo local, ignorado pelo git) sem login
//          "supabase" → exige login (Supabase Auth) e carrega o conteúdo do banco atrás de RLS
// A chave anon do Supabase é pública por desenho; a proteção é RLS + self-signup desligado.
window.ROTA27_CONFIG = {
  backend: "local",
  supabase: { url: "", anonKey: "" }
};
