// Configuración pública de CVirtual. La clave anon de Supabase es pública por diseño;
// nunca agregues aquí una clave service_role ni secretos de Cloudflare.
window.CVIRTUAL_CONFIG = {
  supabaseUrl: "https://wpzddhmllctdsiuxenss.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndwemRkaG1sbGN0ZHNpdXhlbnNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5NjUyNzQsImV4cCI6MjA5OTU0MTI3NH0.hwSxJ3Sk_RlgbvFyr8S64XRuxW7j55BU4gaIneFTuhY",
  // Recursos incluidos dentro de docs/assets para GitHub Pages.
  assetsBaseUrl: "./assets/",
  // Foto y video se almacenan directamente en buckets privados de Supabase Storage.
  // Ejecuta primero el parche SQL 002_supabase_storage_media.sql.
};
