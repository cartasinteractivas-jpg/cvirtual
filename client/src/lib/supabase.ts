import { createClient, type SupabaseClient } from "@supabase/supabase-js";

declare global {
  interface Window {
    CVIRTUAL_CONFIG?: {
      supabaseUrl?: string;
      supabaseAnonKey?: string;
      assetsBaseUrl?: string;
      registrationEndpoint?: string;
    };
  }
}

const config = window.CVIRTUAL_CONFIG ?? {};

export const hasSupabaseConfig = Boolean(config.supabaseUrl && config.supabaseAnonKey);
export const assetsBaseUrl = (config.assetsBaseUrl?.trim() || "/manus-storage/").replace(/\/?$/, "/");
export const registrationEndpoint = config.registrationEndpoint?.trim() || "";

export const supabase: SupabaseClient | null = hasSupabaseConfig
  ? createClient(config.supabaseUrl!, config.supabaseAnonKey!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
    })
  : null;

export async function sendRegistration(formData: FormData) {
  if (!registrationEndpoint || !config.supabaseAnonKey) throw new Error("Falta registrationEndpoint en public/config.js.");
  const response = await fetch(registrationEndpoint, { method: "POST", headers: { apikey: config.supabaseAnonKey, Authorization: `Bearer ${config.supabaseAnonKey}` }, body: formData });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "No se pudo enviar el registro.");
  return result as { candidateId: string; qrUrl?: string | null; initialUsername?: string; temporaryPassword?: string };
}
