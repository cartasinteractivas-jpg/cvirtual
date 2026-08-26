/**
 * Style reminder — Escenario de Trayectorias: retratos laborales reales sobre
 * fondo audiovisual, bandeja editorial móvil, Naranja Señal para los avances.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  BriefcaseBusiness,
  Check,
  ChevronDown,
  CircleAlert,
  CircleCheck,
  FileVideo,
  GraduationCap,
  ImagePlus,
  Loader2,
  LockKeyhole,
  MapPin,
  Plus,
  ReceiptText,
  ShieldCheck,
  Sparkles,
  Trash2,
  Upload,
  UserRound,
  Video,
  WalletCards,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { assetsBaseUrl, ensureAnonymousSession, hasSupabaseConfig, supabase } from "@/lib/supabase";
import { toast } from "sonner";

const assetUrl = (filename: string) => `${assetsBaseUrl}${filename}`;
const videoUrl = assetUrl("cvirtual-welcome-montage_4e9af63c.mp4");
const sceneImages = [
  assetUrl("cvirtual-professional-greeting_bf6a6b47.jpg"),
  assetUrl("cvirtual-construction-worker_bb8502a2.jpg"),
  assetUrl("cvirtual-cleaning-worker_26e776c3.jpg"),
];
const brandMark = assetUrl("cvirtual-mark_b4da5426.png");

type Experience = { company_name: string; position_title: string; start_date: string; end_date: string; is_current: boolean; description: string };
type Education = { institution_name: string; degree_or_program: string; start_date: string; end_date: string; is_current: boolean };
type FormState = {
  first_name: string; last_name: string; email: string; whatsapp_phone: string; city: string;
  headline: string; professional_summary: string; payment_amount: string; yape_operation_code: string; payer_phone: string;
  experience: Experience[]; education: Education[]; photo: File | null; video: File | null; payment_proof: File | null;
  terms: boolean; publication: boolean;
};

const initialExperience = (): Experience => ({ company_name: "", position_title: "", start_date: "", end_date: "", is_current: false, description: "" });
const initialEducation = (): Education => ({ institution_name: "", degree_or_program: "", start_date: "", end_date: "", is_current: false });
const initialForm: FormState = {
  first_name: "", last_name: "", email: "", whatsapp_phone: "", city: "", headline: "", professional_summary: "",
  payment_amount: "", yape_operation_code: "", payer_phone: "", experience: [initialExperience()], education: [initialEducation()],
  photo: null, video: null, payment_proof: null, terms: false, publication: false,
};

const steps = [
  { id: "perfil", label: "Perfil", icon: UserRound, eyebrow: "01 · Tu presentación", title: "Empecemos por tu perfil", copy: "Escribe los datos que deben acompañar tu presentación profesional." },
  { id: "experiencia", label: "Experiencia", icon: BriefcaseBusiness, eyebrow: "02 · Tu experiencia", title: "Cuenta dónde has trabajado", copy: "Puedes agregar más de una experiencia. No necesitas usar un formato complicado." },
  { id: "estudios", label: "Estudios", icon: GraduationCap, eyebrow: "03 · Tu formación", title: "Incluye tus estudios", copy: "Registra los estudios, cursos o formación que quieres mostrar." },
  { id: "archivos", label: "Archivos", icon: Video, eyebrow: "04 · Tu material", title: "Muestra tu perfil en imagen y video", copy: "Tu foto y video se preparan para una carga privada y revisión del equipo." },
  { id: "pago", label: "Pago", icon: WalletCards, eyebrow: "05 · Validación", title: "Registra tu pago por Yape", copy: "Sube tu comprobante para que el equipo pueda validar tu inscripción." },
  { id: "revisar", label: "Enviar", icon: Check, eyebrow: "06 · Último paso", title: "Revisa y envía tu registro", copy: "Al enviarlo recibirás un QR con estado «En construcción» mientras revisamos tu información." },
];

const sceneMeta = [
  { number: "01", office: "Oficina · salud", title: "Presenta tu experiencia", copy: "Crea tu perfil, adjunta tus archivos y recibe un QR para revisión." },
  { number: "02", office: "Obra · construcción", title: "Registra lo que sabes hacer", copy: "Cada oficio tiene una historia concreta que merece compartirse." },
  { number: "03", office: "Espacio · limpieza", title: "Deja tus datos listos", copy: "El equipo revisa tu pago, video y perfil antes de publicarlo." },
];

function formatFileSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function FileCard({ type, file, preview, accept, onChange, onRemove, note }: { type: "photo" | "video" | "proof"; file: File | null; preview?: string; accept: string; onChange: (file: File | null) => void; onRemove: () => void; note: string }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const Icon = type === "photo" ? ImagePlus : type === "video" ? FileVideo : ReceiptText;
  const title = type === "photo" ? "Foto de perfil" : type === "video" ? "Video de presentación" : "Comprobante Yape";
  return (
    <section className="file-card">
      <input className="sr-only" ref={inputRef} type="file" accept={accept} onChange={(event) => onChange(event.target.files?.[0] ?? null)} />
      {file ? (
        <div className="file-ready">
          <div className="file-preview">
            {type === "photo" && preview ? <img src={preview} alt="Vista previa de foto" /> : type === "video" && preview ? <video src={preview} muted playsInline /> : type === "proof" && file.type === "application/pdf" ? <ReceiptText size={22} /> : preview ? <img src={preview} alt="Vista previa del comprobante" /> : <Icon size={22} />}
          </div>
          <div className="file-copy"><strong>{title}</strong><span>{file.name} · {formatFileSize(file.size)}</span></div>
          <button className="icon-button" onClick={onRemove} aria-label={`Quitar ${title}`}><X size={18} /></button>
        </div>
      ) : (
        <button type="button" className="file-empty" onClick={() => inputRef.current?.click()}>
          <span className="upload-orb"><Icon size={20} /></span>
          <span><strong>{title}</strong><small>{note}</small></span>
          <Upload size={18} />
        </button>
      )}
    </section>
  );
}

export default function Home() {
  const [step, setStep] = useState(0);
  const [intro, setIntro] = useState(true);
  const [showSkip, setShowSkip] = useState(false);
  const [scene, setScene] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [form, setForm] = useState<FormState>(initialForm);
  const [photoPreview, setPhotoPreview] = useState("");
  const [videoPreview, setVideoPreview] = useState("");
  const [proofPreview, setProofPreview] = useState("");

  const active = steps[step];
  const progress = Math.round(((step + 1) / steps.length) * 100);
  const activeScene = sceneMeta[scene];

  useEffect(() => {
    const skipTimer = window.setTimeout(() => setShowSkip(true), 3000);
    const sceneTimer = window.setInterval(() => setScene((current) => (current + 1) % 3), 3400);
    return () => { window.clearTimeout(skipTimer); window.clearInterval(sceneTimer); };
  }, []);

  useEffect(() => {
    const url = form.photo ? URL.createObjectURL(form.photo) : "";
    setPhotoPreview(url);
    return () => { if (url) URL.revokeObjectURL(url); };
  }, [form.photo]);
  useEffect(() => {
    const url = form.video ? URL.createObjectURL(form.video) : "";
    setVideoPreview(url);
    return () => { if (url) URL.revokeObjectURL(url); };
  }, [form.video]);
  useEffect(() => {
    const url = form.payment_proof ? URL.createObjectURL(form.payment_proof) : "";
    setProofPreview(url);
    return () => { if (url) URL.revokeObjectURL(url); };
  }, [form.payment_proof]);

  const fullName = useMemo(() => `${form.first_name} ${form.last_name}`.trim() || "Tu nombre aparecerá aquí", [form.first_name, form.last_name]);
  const update = <K extends keyof FormState>(key: K, value: FormState[K]) => setForm((previous) => ({ ...previous, [key]: value }));
  const updateExperience = (index: number, key: keyof Experience, value: string | boolean) => setForm((previous) => ({ ...previous, experience: previous.experience.map((item, idx) => idx === index ? { ...item, [key]: value } : item) }));
  const updateEducation = (index: number, key: keyof Education, value: string | boolean) => setForm((previous) => ({ ...previous, education: previous.education.map((item, idx) => idx === index ? { ...item, [key]: value } : item) }));

  const stepIsValid = () => {
    if (step === 0) return Boolean(form.first_name && form.last_name && form.email && form.whatsapp_phone && form.headline && form.professional_summary);
    if (step === 1) return form.experience.some((item) => item.company_name && item.position_title);
    if (step === 2) return form.education.some((item) => item.institution_name && item.degree_or_program);
    if (step === 3) return Boolean(form.photo && form.video);
    if (step === 4) return Boolean(Number(form.payment_amount) > 0 && form.yape_operation_code && form.payment_proof);
    return form.terms && form.publication;
  };

  const goNext = () => {
    if (!stepIsValid()) { toast.error("Completa los datos marcados para continuar."); return; }
    if (step < steps.length - 1) setStep((current) => current + 1); else void submitRegistration();
  };

  async function uploadCandidateMedia(file: File, kind: "photo" | "video", candidateId: string) {
    if (!supabase) throw new Error("Supabase no está configurado.");
    const bucket = kind === "photo" ? "candidate-photos" : "candidate-videos";
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "-");
    const path = `${candidateId}/${kind}-${Date.now()}-${safeName}`;
    const { error: uploadError } = await supabase.storage.from(bucket).upload(path, file, { upsert: false, contentType: file.type });
    if (uploadError) throw new Error(`No se pudo cargar ${kind === "photo" ? "la foto" : "el video"}: ${uploadError.message}`);

    const { error: mediaError } = await supabase.from("candidate_media").insert({
      candidate_id: candidateId,
      media_type: kind === "photo" ? "image" : "video",
      provider: "external",
      provider_asset_id: path,
      media_status: "uploading",
      visibility: "private",
      is_background: false,
      metadata: { storage_provider: "supabase_storage", storage_bucket: bucket, storage_path: path, original_filename: file.name },
    });
    if (mediaError) throw new Error(`El archivo se cargó, pero no se pudo vincular al perfil: ${mediaError.message}`);
  }

  async function submitRegistration() {
    if (!hasSupabaseConfig || !supabase) { toast.error("Falta la configuración de Supabase en public/config.js."); return; }
    setSubmitting(true);
    try {
      const user = await ensureAnonymousSession();
      const { data: candidate, error: candidateError } = await supabase.from("candidate_profiles").insert({
        owner_user_id: user.id, first_name: form.first_name.trim(), last_name: form.last_name.trim(), email: form.email.trim(),
        whatsapp_phone: form.whatsapp_phone.trim(), phone: form.whatsapp_phone.trim(), city: form.city.trim() || null,
        headline: form.headline.trim(), professional_summary: form.professional_summary.trim(), accepts_terms_at: new Date().toISOString(),
        allows_publication_at: new Date().toISOString(), registration_source: "cvirtual-github-pages",
      }).select("id").single();
      if (candidateError || !candidate) throw new Error(candidateError?.message || "No se pudo crear el perfil.");

      const experiences = form.experience.filter((item) => item.company_name && item.position_title).map((item, index) => ({ ...item, candidate_id: candidate.id, display_order: index, end_date: item.is_current ? null : item.end_date ? `${item.end_date}-01` : null, start_date: item.start_date ? `${item.start_date}-01` : null }));
      const education = form.education.filter((item) => item.institution_name && item.degree_or_program).map((item, index) => ({ ...item, candidate_id: candidate.id, display_order: index, end_date: item.is_current ? null : item.end_date ? `${item.end_date}-01` : null, start_date: item.start_date ? `${item.start_date}-01` : null }));
      if (experiences.length) { const { error } = await supabase.from("candidate_experiences").insert(experiences); if (error) throw new Error(error.message); }
      if (education.length) { const { error } = await supabase.from("candidate_education").insert(education); if (error) throw new Error(error.message); }

      const safeProofName = form.payment_proof!.name.replace(/[^a-zA-Z0-9._-]/g, "-");
      const proofPath = `${candidate.id}/yape-${Date.now()}-${safeProofName}`;
      const { error: proofUploadError } = await supabase.storage.from("payment-proofs").upload(proofPath, form.payment_proof!, { upsert: false, contentType: form.payment_proof!.type });
      if (proofUploadError) throw new Error(`No se pudo cargar el comprobante: ${proofUploadError.message}`);
      const { error: paymentError } = await supabase.from("candidate_payments").insert({ candidate_id: candidate.id, method: "yape", amount: Number(form.payment_amount), currency: "PEN", yape_operation_code: form.yape_operation_code.trim(), payer_phone: form.payer_phone.trim() || null, proof_storage_bucket: "payment-proofs", proof_storage_path: proofPath });
      if (paymentError) throw new Error(paymentError.message);

      await uploadCandidateMedia(form.photo!, "photo", candidate.id);
      await uploadCandidateMedia(form.video!, "video", candidate.id);
      toast.success("Foto y video privados cargados correctamente.");

      const { error: submitError } = await supabase.rpc("submit_candidate_profile", { p_candidate_id: candidate.id });
      if (submitError) throw new Error(submitError.message);
      setSubmitted(true);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Ocurrió un problema al guardar el registro.");
    } finally { setSubmitting(false); }
  }

  if (submitted) return <SuccessScreen fullName={fullName} onRestart={() => { setForm(initialForm); setStep(0); setSubmitted(false); }} />;

  return (
    <main className="registration-shell">
      <section className="scene-stage" aria-label="Presentación CVirtual">
        <video className="hero-video" src={videoUrl} autoPlay muted loop playsInline poster={sceneImages[0]} />
        <div className="scene-fallback" aria-hidden="true">{sceneImages.map((image, index) => <img key={image} src={image} className={cn(index === scene ? "active" : "")} alt="" />)}</div>
        <div className="ink-overlay" />
        <header className="brand-bar">
          <a className="brand" href="#inicio" aria-label="CVirtual inicio"><span className="brand-symbol"><img src={brandMark} alt="" /></span><span className="brand-type"><strong><b>CV</b>irtual</strong><small>PERFILES QUE SE COMPARTEN</small></span></a>
          <div className="secure-mark"><LockKeyhole size={14} /> Datos protegidos</div>
        </header>
        <div className="scene-copy" id="inicio">
          <div className="frame-rule" aria-hidden="true" />
          <div className="scene-marker"><span>ESCENA {activeScene.number} / 03</span><b>{activeScene.office}</b></div>
          <p className="eyebrow light"><span className="pulse-dot" /> Registro de perfil virtual</p>
          <h1>{activeScene.title}<br /><em>en tu QR.</em></h1>
          <p className="scene-caption">{activeScene.copy}</p>
        </div>
        <div className="scene-indicators" aria-label="Escenas de presentación">{["Oficina", "Construcción", "Limpieza"].map((item, index) => <button key={item} onClick={() => setScene(index)} className={cn("scene-dot", scene === index && "selected")} aria-label={`Ver escena ${item}`}><span />{item}</button>)}</div>
        {intro && <div className="intro-card"><div className="intro-step"><span>PASO 01 / 06</span><b>PERFIL BASE</b></div><p>Prepara tus datos, experiencias, archivos y comprobante para iniciar la revisión.</p><Button onClick={() => { setIntro(false); setStep(0); }}><Sparkles size={17} /> Empezar mi registro <ArrowRight size={17} /></Button></div>}
        {showSkip && intro && <button className="skip-button" onClick={() => setIntro(false)}>Saltar presentación <ArrowRight size={15} /></button>}
      </section>

      {!intro && <section className="form-sheet" aria-live="polite">
        <div className="sheet-topline"><span>Registro CVirtual</span><span>{progress}% completo</span></div>
        <div className="progress-line"><span style={{ width: `${progress}%` }} /></div>
        <div className="step-rail">{steps.map((item, index) => <button key={item.id} className={cn("step-rail-item", index === step && "current", index < step && "done")} onClick={() => { if (index <= step) setStep(index); }} aria-label={`Paso ${index + 1}: ${item.label}`}><span>{index < step ? <Check size={13} /> : String(index + 1).padStart(2, "0")}</span><b>{item.label}</b></button>)}</div>
        <div className="form-content">
          <header className="form-heading"><p className="eyebrow orange">{active.eyebrow}</p><h2>{active.title}</h2><p>{active.copy}</p></header>
          {step === 0 && <ProfileStep form={form} update={update} />}
          {step === 1 && <ExperienceStep items={form.experience} onUpdate={updateExperience} onAdd={() => update("experience", [...form.experience, initialExperience()])} onRemove={(index) => update("experience", form.experience.filter((_, itemIndex) => itemIndex !== index))} />}
          {step === 2 && <EducationStep items={form.education} onUpdate={updateEducation} onAdd={() => update("education", [...form.education, initialEducation()])} onRemove={(index) => update("education", form.education.filter((_, itemIndex) => itemIndex !== index))} />}
          {step === 3 && <FilesStep form={form} photoPreview={photoPreview} videoPreview={videoPreview} update={update} />}
          {step === 4 && <PaymentStep form={form} proofPreview={proofPreview} update={update} />}
          {step === 5 && <ReviewStep form={form} fullName={fullName} update={update} />}
        </div>
        <footer className="form-footer"><Button variant="ghost" className="back-button" disabled={step === 0} onClick={() => setStep((current) => current - 1)}><ArrowLeft size={17} /> Atrás</Button><Button className="next-button" onClick={goNext} disabled={submitting}>{submitting ? <><Loader2 className="animate-spin" size={18} /> Enviando...</> : step === steps.length - 1 ? <>Enviar a revisión <Check size={18} /></> : <>Continuar <ArrowRight size={18} /></>}</Button></footer>
      </section>}
    </main>
  );
}

function ProfileStep({ form, update }: { form: FormState; update: <K extends keyof FormState>(key: K, value: FormState[K]) => void }) {
  return <div className="field-stack"><div className="two-fields"><Field label="Nombres" required><Input value={form.first_name} onChange={(e) => update("first_name", e.target.value)} placeholder="Ej. María Elena" /></Field><Field label="Apellidos" required><Input value={form.last_name} onChange={(e) => update("last_name", e.target.value)} placeholder="Ej. Flores Ramos" /></Field></div><Field label="Correo electrónico" required><Input type="email" value={form.email} onChange={(e) => update("email", e.target.value)} placeholder="tucorreo@email.com" /></Field><div className="two-fields"><Field label="WhatsApp" required><Input inputMode="tel" value={form.whatsapp_phone} onChange={(e) => update("whatsapp_phone", e.target.value)} placeholder="+51 999 999 999" /></Field><Field label="Ciudad"><Input value={form.city} onChange={(e) => update("city", e.target.value)} placeholder="Ej. Lima" /></Field></div><Field label="Título profesional" required hint="Lo primero que verá quien abra tu QR."><Input value={form.headline} onChange={(e) => update("headline", e.target.value)} placeholder="Ej. Auxiliar de enfermería" /></Field><Field label="Perfil profesional" required hint="Describe tu experiencia, fortalezas y el tipo de oportunidad que buscas."><Textarea rows={5} value={form.professional_summary} onChange={(e) => update("professional_summary", e.target.value)} placeholder="Tengo experiencia en atención al cliente, trabajo en equipo y..." /></Field></div>;
}

function ExperienceStep({ items, onUpdate, onAdd, onRemove }: { items: Experience[]; onUpdate: (index: number, key: keyof Experience, value: string | boolean) => void; onAdd: () => void; onRemove: (index: number) => void }) {
  return <div className="repeater-stack">{items.map((item, index) => <div className="repeater-card" key={index}><div className="repeater-title"><span>Experiencia {String(index + 1).padStart(2, "0")}</span>{items.length > 1 && <button onClick={() => onRemove(index)}><Trash2 size={16} /> Quitar</button>}</div><Field label="Empresa o lugar de trabajo" required><Input value={item.company_name} onChange={(e) => onUpdate(index, "company_name", e.target.value)} placeholder="Ej. Clínica Santa Rosa" /></Field><Field label="Puesto o función" required><Input value={item.position_title} onChange={(e) => onUpdate(index, "position_title", e.target.value)} placeholder="Ej. Asistente de atención" /></Field><div className="two-fields"><Field label="Inicio"><Input type="month" value={item.start_date} onChange={(e) => onUpdate(index, "start_date", e.target.value)} /></Field><Field label="Fin"><Input type="month" value={item.end_date} disabled={item.is_current} onChange={(e) => onUpdate(index, "end_date", e.target.value)} /></Field></div><label className="check-row"><input type="checkbox" checked={item.is_current} onChange={(e) => onUpdate(index, "is_current", e.target.checked)} /><span>Actualmente trabajo aquí</span></label><Field label="Qué hacías en este trabajo"><Textarea rows={3} value={item.description} onChange={(e) => onUpdate(index, "description", e.target.value)} placeholder="Ej. Atención a pacientes, coordinación de citas..." /></Field></div>)}<button className="add-row" onClick={onAdd}><Plus size={17} /> Agregar otra experiencia</button></div>;
}

function EducationStep({ items, onUpdate, onAdd, onRemove }: { items: Education[]; onUpdate: (index: number, key: keyof Education, value: string | boolean) => void; onAdd: () => void; onRemove: (index: number) => void }) {
  return <div className="repeater-stack">{items.map((item, index) => <div className="repeater-card" key={index}><div className="repeater-title"><span>Formación {String(index + 1).padStart(2, "0")}</span>{items.length > 1 && <button onClick={() => onRemove(index)}><Trash2 size={16} /> Quitar</button>}</div><Field label="Institución" required><Input value={item.institution_name} onChange={(e) => onUpdate(index, "institution_name", e.target.value)} placeholder="Ej. Instituto Superior Tecnológico" /></Field><Field label="Carrera, curso o programa" required><Input value={item.degree_or_program} onChange={(e) => onUpdate(index, "degree_or_program", e.target.value)} placeholder="Ej. Técnico en Enfermería" /></Field><div className="two-fields"><Field label="Inicio"><Input type="month" value={item.start_date} onChange={(e) => onUpdate(index, "start_date", e.target.value)} /></Field><Field label="Fin"><Input type="month" value={item.end_date} disabled={item.is_current} onChange={(e) => onUpdate(index, "end_date", e.target.value)} /></Field></div><label className="check-row"><input type="checkbox" checked={item.is_current} onChange={(e) => onUpdate(index, "is_current", e.target.checked)} /><span>Actualmente estudio aquí</span></label></div>)}<button className="add-row" onClick={onAdd}><Plus size={17} /> Agregar otra formación</button></div>;
}

function FilesStep({ form, photoPreview, videoPreview, update }: { form: FormState; photoPreview: string; videoPreview: string; update: <K extends keyof FormState>(key: K, value: FormState[K]) => void }) {
  return <div className="field-stack"><div className="upload-intro"><ShieldCheck size={20} /><p>Los archivos se mostrarán solo después de que tu perfil haya sido revisado y publicado.</p></div><FileCard type="photo" file={form.photo} preview={photoPreview} accept="image/jpeg,image/png,image/webp" onChange={(file) => update("photo", file)} onRemove={() => update("photo", null)} note="JPG, PNG o WEBP · máximo 5 MB" /><FileCard type="video" file={form.video} preview={videoPreview} accept="video/mp4,video/webm,video/quicktime" onChange={(file) => update("video", file)} onRemove={() => update("video", null)} note="MP4, WEBM o MOV · máximo 100 MB" /><div className="tip-card"><Video size={17} /><span>Graba un video breve, de frente y con buena luz. Preséntate, cuenta qué haces y qué oportunidad buscas.</span></div></div>;
}

function PaymentStep({ form, proofPreview, update }: { form: FormState; proofPreview: string; update: <K extends keyof FormState>(key: K, value: FormState[K]) => void }) {
  return <div className="field-stack"><div className="payment-banner"><div className="yape-ring">Y</div><div><strong>Pago por Yape</strong><span>Adjunta la captura de tu operación para pasar a revisión.</span></div></div><Field label="Monto pagado (S/)" required><Input type="number" min="0.01" step="0.01" inputMode="decimal" value={form.payment_amount} onChange={(e) => update("payment_amount", e.target.value)} placeholder="Ej. 25.00" /></Field><Field label="Código de operación Yape" required><Input value={form.yape_operation_code} onChange={(e) => update("yape_operation_code", e.target.value)} placeholder="Ej. 12345678" /></Field><Field label="Teléfono desde el que pagaste"><Input inputMode="tel" value={form.payer_phone} onChange={(e) => update("payer_phone", e.target.value)} placeholder="+51 999 999 999" /></Field><FileCard type="proof" file={form.payment_proof} preview={proofPreview} accept="image/jpeg,image/png,application/pdf" onChange={(file) => update("payment_proof", file)} onRemove={() => update("payment_proof", null)} note="Captura JPG, PNG o PDF · máximo 10 MB" /><p className="small-note"><LockKeyhole size={14} /> Tu comprobante es privado: solo lo verá el equipo encargado de validar tu pago.</p></div>;
}

function ReviewStep({ form, fullName, update }: { form: FormState; fullName: string; update: <K extends keyof FormState>(key: K, value: FormState[K]) => void }) {
  const photoUrl = form.photo ? URL.createObjectURL(form.photo) : "";
  useEffect(() => () => { if (photoUrl) URL.revokeObjectURL(photoUrl); }, [photoUrl]);
  return <div className="field-stack"><div className="review-card"><div className="review-avatar">{photoUrl ? <img src={photoUrl} alt="" /> : <UserRound size={26} />}</div><div><span>Perfil preparado</span><strong>{fullName}</strong><p>{form.headline || "Tu título profesional"}</p></div><CircleCheck size={22} /></div><div className="review-list"><p><UserRound size={16} /> Perfil y datos de contacto</p><p><BriefcaseBusiness size={16} /> {form.experience.filter((item) => item.company_name).length} experiencia(s) registrada(s)</p><p><GraduationCap size={16} /> {form.education.filter((item) => item.institution_name).length} estudio(s) registrado(s)</p><p><ReceiptText size={16} /> Comprobante Yape preparado</p></div><label className="consent-row"><input type="checkbox" checked={form.terms} onChange={(e) => update("terms", e.target.checked)} /><span>Acepto el tratamiento de mis datos para registrar y revisar mi perfil.</span></label><label className="consent-row"><input type="checkbox" checked={form.publication} onChange={(e) => update("publication", e.target.checked)} /><span>Autorizo la publicación de los datos seleccionados cuando mi perfil sea aprobado.</span></label><div className="info-strip"><CircleAlert size={17} /><span>El QR se genera al registrar tu perfil. Antes de la aprobación mostrará «En construcción».</span></div></div>;
}

function Field({ label, required, hint, children }: { label: string; required?: boolean; hint?: string; children: React.ReactNode }) { return <label className="field"><span>{label}{required && <i> *</i>}</span>{children}{hint && <small>{hint}</small>}</label>; }

function SuccessScreen({ fullName, onRestart }: { fullName: string; onRestart: () => void }) { return <main className="success-screen"><div className="success-stage"><img src={brandMark} alt="" /><p className="eyebrow orange">Registro enviado</p><h1>Gracias, <em>{fullName}.</em></h1><p>Tu perfil y comprobante han sido enviados a revisión. Cuando el pago y los datos sean validados, el equipo preparará tu QR y publicación.</p><div className="success-status"><span><Check size={15} /></span> Perfil en revisión</div><Button onClick={onRestart} variant="outline">Registrar otra persona</Button></div></main>; }
