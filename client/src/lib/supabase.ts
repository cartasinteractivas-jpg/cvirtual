import { createClient, type SupabaseClient } from "@supabase/supabase-js";

declare global {
  interface Window {
    CVIRTUAL_CONFIG?: {
      supabaseUrl?: string;
      supabaseAnonKey?: string;
      assetsBaseUrl?: string;
    };
  }
}

const config = window.CVIRTUAL_CONFIG ?? {};

export const hasSupabaseConfig = Boolean(config.supabaseUrl && config.supabaseAnonKey);
export const assetsBaseUrl = (config.assetsBaseUrl?.trim() || "/manus-storage/").replace(/\/?$/, "/");

export const supabase: SupabaseClient | null = hasSupabaseConfig
  ? createClient(config.supabaseUrl!, config.supabaseAnonKey!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
    })
  : null;

export async function ensureAnonymousSession() {
  if (!supabase) throw new Error("Falta la configuración pública de Supabase.");

  const { data: current } = await supabase.auth.getSession();
  if (current.session?.user) return current.session.user;

  const { data, error } = await supabase.auth.signInAnonymously();
  if (error || !data.user) {
    throw new Error(
      "No fue posible iniciar la sesión de registro. Activa Anonymous Sign-Ins en Supabase Authentication > Providers.",
    );
  }
  return data.user;
}
