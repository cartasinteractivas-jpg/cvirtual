// CVirtual intake: registra perfiles sin requerir Anonymous Sign-Ins en el navegador.
// Despliegue: supabase functions deploy register-profile --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://cartasinteractivas-jpg.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) throw new Error("Faltan los secretos de Supabase en la función.");
    const admin = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
    const data = await request.formData();
    const text = (key: string) => String(data.get(key) ?? "").trim();
    const nonce = crypto.randomUUID();
    const actualEmail = text("email");
    const dni = text("dni");
    if (!/^[0-9]{8}$/.test(dni)) throw new Error("El DNI debe tener exactamente 8 dígitos.");
    const loginEmail = `dni-${dni}@usuarios.cvirtual.local`;
    const temporaryPassword = `CV-${crypto.randomUUID().replaceAll("-", "").slice(0, 10)}`;

    // Cada alta pública recibe un propietario técnico temporal. Después el cliente
    // activa su propio acceso desde cvirtual_adm y el administrador lo vincula.
    const { data: owner, error: ownerError } = await admin.auth.admin.createUser({
      email: loginEmail,
      password: temporaryPassword,
      email_confirm: true,
    });
    if (ownerError || !owner.user) throw new Error(ownerError?.message || "No se pudo preparar el registro.");

    const { data: candidate, error: candidateError } = await admin.from("candidate_profiles").insert({
      owner_user_id: owner.user.id,
      dni,
      first_name: text("first_name") || "Perfil",
      last_name: text("last_name") || "pendiente",
      display_name: text("display_name") || null,
      email: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(actualEmail) ? actualEmail : loginEmail,
      whatsapp_phone: text("whatsapp_phone") || null,
      phone: text("whatsapp_phone") || null,
      city: text("city") || null,
      headline: text("headline") || null,
      professional_summary: text("professional_summary") || null,
      accepts_terms_at: text("terms") === "true" ? new Date().toISOString() : null,
      allows_publication_at: text("publication") === "true" ? new Date().toISOString() : null,
      registration_source: "cvirtual-public-intake",
    }).select("id").single();
    if (candidateError || !candidate) {
      await admin.auth.admin.deleteUser(owner.user.id);
      throw new Error(candidateError?.message || "No se pudo crear el perfil.");
    }

    const uploadFile = async (field: string, bucket: string, kind: "photo" | "video" | "proof", limit: number) => {
      const file = data.get(field);
      if (!(file instanceof File) || !file.size) return null;
      if (file.size > limit) throw new Error(`${kind === "video" ? "El video" : "El archivo"} excede el tamaño permitido.`);
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "-");
      const path = `${candidate.id}/${kind}-${Date.now()}-${safeName}`;
      const { error } = await admin.storage.from(bucket).upload(path, file, { contentType: file.type, upsert: false });
      if (error) throw new Error(`No se pudo guardar ${kind}: ${error.message}`);
      return { path, name: file.name, type: file.type };
    };

    const photo = await uploadFile("photo", "candidate-photos", "photo", 5 * 1024 * 1024);
    const video = await uploadFile("video", "candidate-videos", "video", 100 * 1024 * 1024);
    const proof = await uploadFile("payment_proof", "payment-proofs", "proof", 10 * 1024 * 1024);

    const experiences = JSON.parse(text("experiences") || "[]").filter((item: Record<string, string>) => item.company_name || item.position_title)
      .map((item: Record<string, string>, index: number) => ({ candidate_id: candidate.id, company_name: item.company_name || "Experiencia por completar", position_title: item.position_title || "Por definir", start_date: item.start_date ? `${item.start_date}-01` : null, end_date: item.is_current ? null : item.end_date ? `${item.end_date}-01` : null, is_current: item.is_current === true, description: item.description || null, display_order: index }));
    if (experiences.length) await admin.from("candidate_experiences").insert(experiences);

    const education = JSON.parse(text("education") || "[]").filter((item: Record<string, string>) => item.institution_name || item.degree_or_program)
      .map((item: Record<string, string>, index: number) => ({ candidate_id: candidate.id, institution_name: item.institution_name || "Formación por completar", degree_or_program: item.degree_or_program || "Por definir", start_date: item.start_date ? `${item.start_date}-01` : null, end_date: item.is_current ? null : item.end_date ? `${item.end_date}-01` : null, is_current: item.is_current === true, display_order: index }));
    if (education.length) await admin.from("candidate_education").insert(education);

    if (photo) await admin.from("candidate_media").insert({ candidate_id: candidate.id, media_type: "image", provider: "external", provider_asset_id: photo.path, media_status: "ready", visibility: "private", metadata: { storage_provider: "supabase_storage", storage_bucket: "candidate-photos", storage_path: photo.path, original_filename: photo.name } });
    if (video) await admin.from("candidate_media").insert({ candidate_id: candidate.id, media_type: "video", provider: "external", provider_asset_id: video.path, media_status: "ready", visibility: "private", metadata: { storage_provider: "supabase_storage", storage_bucket: "candidate-videos", storage_path: video.path, original_filename: video.name, pending_editor_review: true } });

    await admin.from("candidate_payments").insert({
      candidate_id: candidate.id, method: "yape", amount: 40, currency: "PEN", payment_status: "pending",
      yape_operation_code: text("yape_operation_code") || `REG-${candidate.id.replaceAll("-", "").slice(0, 16)}`,
      payer_phone: text("payer_phone") || null, proof_storage_bucket: "payment-proofs", proof_storage_path: proof?.path || null,
      metadata: { price_type: "initial_registration", listed_price_pen: 40 },
    });

    const [{ data: qr }, { data: settings }] = await Promise.all([
      admin.from("candidate_qr_codes").select("token").eq("candidate_id", candidate.id).single(),
      admin.from("platform_settings").select("public_web_base_url").eq("singleton", true).single(),
    ]);
    const base = String(settings?.public_web_base_url || "https://cartasinteractivas-jpg.github.io/cvirtual").replace(/\/$/, "");
    return json({ candidateId: candidate.id, qrUrl: qr?.token ? `${base}/cv.html?code=${qr.token}` : null, initialUsername: dni, temporaryPassword });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "No se pudo registrar el perfil." }, 400);
  }
});
