// ROTA 27 · configuração pública (vai para o repositório)
// backend: "local"    → usa data/routes.js (arquivo local, ignorado pelo git) sem login
//          "supabase" → exige login (Supabase Auth) e carrega o conteúdo do banco atrás de RLS
// A chave anon do Supabase é pública por desenho; a proteção é RLS + self-signup desligado.
window.ROTA27_CONFIG = {
  backend: "local",
  supabase: { url: "https://tjsfaraduwgfkyisqkwg.supabase.co", anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqc2ZhcmFkdXdnZmt5aXNxa3dnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMjY2MjcsImV4cCI6MjA5ODcwMjYyN30.ONO2gyoIhjBwW7RFTiEDtH9J3vojeCyRCwDwM7n6VME" }
};
