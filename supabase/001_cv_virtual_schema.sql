-- =============================================================================
-- CV VIRTUAL CON QR, PAGOS Y VIDEO EN CLOUDFLARE
-- Migración para Supabase/PostgreSQL
--
-- Alcance:
--   1. Registro de currículos virtuales por usuario autenticado.
--   2. Experiencia, estudios, preguntas predefinidas y datos de contacto.
--   3. Pagos por Yape con comprobante privado en Supabase Storage.
--   4. QR único por currículo y página pública de estado/contenido.
--   5. Video o imagen de fondo alojado en Cloudflare; aquí solo se guarda
--      la referencia, nunca credenciales de Cloudflare.
--   6. Flujo: borrador -> pago pendiente -> revisión -> aprobado -> publicado.
--   7. Alertas de nuevos registros para el panel administrativo.
--
-- Antes de ejecutar:
--   - Cambia platform_settings.public_web_base_url por tu URL real de GitHub Pages.
--   - Crea el primer administrador en public.staff_roles desde SQL Editor usando
--     el UUID de auth.users del administrador.
--   - Ejecuta esta migración una sola vez en un proyecto nuevo o revisa conflictos.
-- =============================================================================

begin;

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public;

-- -----------------------------------------------------------------------------
-- TIPOS DEL DOMINIO
-- -----------------------------------------------------------------------------
do $$
begin
  create type public.candidate_status as enum (
    'draft',
    'payment_pending',
    'under_review',
    'approved',
    'published',
    'rejected',
    'suspended',
    'archived'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.payment_method as enum ('yape', 'plin', 'cash', 'bank_transfer', 'other');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.payment_status as enum ('pending', 'paid', 'rejected', 'refunded', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.media_type as enum ('video', 'image');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.media_provider as enum ('cloudflare_stream', 'cloudflare_r2', 'external');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.media_status as enum ('uploading', 'ready', 'failed', 'disabled');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.media_visibility as enum ('private', 'unlisted', 'public');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.question_type as enum ('single_choice', 'multiple_choice', 'short_text', 'long_text', 'boolean');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.staff_role as enum ('admin', 'reviewer', 'publisher', 'finance', 'support');
exception when duplicate_object then null;
end $$;

-- -----------------------------------------------------------------------------
-- CONFIGURACIÓN DE LA PLATAFORMA
-- -----------------------------------------------------------------------------
create table if not exists public.platform_settings (
  singleton boolean primary key default true check (singleton),
  public_web_base_url text not null default 'https://cartasinteractivas-jpg.github.io/cvirtual',
  support_whatsapp_phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public.platform_settings (singleton)
values (true)
on conflict (singleton) do nothing;

comment on table public.platform_settings is
  'Configuración de la única web matriz. El QR siempre apunta a public_web_base_url/cv.html?code=<token>.';

-- -----------------------------------------------------------------------------
-- USUARIOS INTERNOS Y REGISTROS PRINCIPALES
-- -----------------------------------------------------------------------------
create table if not exists public.staff_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.staff_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  unique (user_id, role)
);

create table if not exists public.candidate_profiles (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,

  -- Información de perfil y contacto.
  first_name text not null check (char_length(trim(first_name)) between 1 and 80),
  last_name text not null check (char_length(trim(last_name)) between 1 and 80),
  display_name text,
  headline text check (headline is null or char_length(headline) <= 160),
  professional_summary text check (professional_summary is null or char_length(professional_summary) <= 5000),
  city text,
  country_code char(2) default 'PE' check (country_code ~ '^[A-Z]{2}$'),
  email text not null check (email ~* '^[^[:space:]@]+@[^[:space:]@]+\\.[^[:space:]@]+$'),
  phone text check (phone is null or phone ~ '^\\+?[1-9][0-9]{6,14}$'),
  whatsapp_phone text check (whatsapp_phone is null or whatsapp_phone ~ '^\\+?[1-9][0-9]{6,14}$'),
  linkedin_url text,
  portfolio_url text,
  website_url text,

  -- Privacidad de datos de contacto en el CV público.
  show_email boolean not null default false,
  show_phone boolean not null default false,
  show_whatsapp boolean not null default true,
  show_location boolean not null default true,

  -- Ajustes de presentación de la página pública.
  public_handle text unique check (public_handle is null or public_handle ~ '^[a-z0-9][a-z0-9-]{2,60}$'),
  presentation_config jsonb not null default '{}'::jsonb check (jsonb_typeof(presentation_config) = 'object'),

  -- Flujo de negocio.
  status public.candidate_status not null default 'draft',
  submitted_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  expires_at timestamptz,
  internal_notes text,

  -- Consentimientos requeridos para el registro.
  accepts_terms_at timestamptz,
  allows_publication_at timestamptz,
  registration_source text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists candidate_profiles_owner_idx on public.candidate_profiles (owner_user_id);
create index if not exists candidate_profiles_status_idx on public.candidate_profiles (status, created_at desc);
create index if not exists candidate_profiles_email_idx on public.candidate_profiles (lower(email));

comment on table public.candidate_profiles is
  'Una fila por currículo virtual. El estado published es la única condición para mostrar datos en el QR público.';

-- -----------------------------------------------------------------------------
-- DETALLE DEL CURRÍCULO
-- -----------------------------------------------------------------------------
create table if not exists public.candidate_experiences (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete cascade,
  company_name text not null check (char_length(trim(company_name)) between 1 and 160),
  position_title text not null check (char_length(trim(position_title)) between 1 and 160),
  employment_type text,
  location text,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  description text,
  display_order smallint not null default 0,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  check (not is_current or end_date is null)
);

create index if not exists candidate_experiences_candidate_idx
  on public.candidate_experiences (candidate_id, display_order, start_date desc);

create table if not exists public.candidate_education (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete cascade,
  institution_name text not null check (char_length(trim(institution_name)) between 1 and 180),
  degree_or_program text not null check (char_length(trim(degree_or_program)) between 1 and 180),
  field_of_study text,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  description text,
  display_order smallint not null default 0,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  check (not is_current or end_date is null)
);

create index if not exists candidate_education_candidate_idx
  on public.candidate_education (candidate_id, display_order, start_date desc);

-- Preguntas configurables para el formulario de registro.
create table if not exists public.questionnaire_questions (
  id uuid primary key default gen_random_uuid(),
  question_key text not null unique check (question_key ~ '^[a-z][a-z0-9_]{2,60}$'),
  question_text text not null check (char_length(trim(question_text)) between 1 and 500),
  help_text text,
  input_type public.question_type not null default 'single_choice',
  is_required boolean not null default false,
  is_active boolean not null default true,
  is_public boolean not null default false,
  display_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.questionnaire_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questionnaire_questions(id) on delete cascade,
  option_value text not null check (char_length(trim(option_value)) between 1 and 160),
  option_label text not null check (char_length(trim(option_label)) between 1 and 160),
  display_order smallint not null default 0,
  is_active boolean not null default true,
  unique (question_id, option_value)
);

create index if not exists questionnaire_options_question_idx
  on public.questionnaire_options (question_id, display_order);

create table if not exists public.candidate_answers (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete cascade,
  question_id uuid not null references public.questionnaire_questions(id) on delete restrict,
  answer_text text,
  boolean_value boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (candidate_id, question_id)
);

create table if not exists public.candidate_answer_options (
  answer_id uuid not null references public.candidate_answers(id) on delete cascade,
  option_id uuid not null references public.questionnaire_options(id) on delete restrict,
  primary key (answer_id, option_id)
);

-- -----------------------------------------------------------------------------
-- MULTIMEDIA: REFERENCIA A CLOUDFLARE, NO ARCHIVO NI CREDENCIALES
-- -----------------------------------------------------------------------------
create table if not exists public.candidate_media (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete cascade,
  media_type public.media_type not null,
  provider public.media_provider not null,
  provider_asset_id text not null,
  playback_url text,
  thumbnail_url text,
  media_status public.media_status not null default 'uploading',
  visibility public.media_visibility not null default 'private',
  is_background boolean not null default false,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  uploaded_by uuid references auth.users(id) on delete set null,
  uploaded_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  unique (provider, provider_asset_id)
);

create unique index if not exists one_background_media_per_candidate_idx
  on public.candidate_media (candidate_id)
  where is_background;

create index if not exists candidate_media_public_ready_idx
  on public.candidate_media (candidate_id, media_status, visibility)
  where is_background;

comment on table public.candidate_media is
  'Guarda el ID y URL de reproducción de Cloudflare Stream o R2. No almacenar API tokens, secretos ni claves R2.';

-- -----------------------------------------------------------------------------
-- COBROS Y COMPROBANTES
-- -----------------------------------------------------------------------------
create table if not exists public.candidate_payments (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_profiles(id) on delete restrict,
  method public.payment_method not null default 'yape',
  amount numeric(12,2) not null check (amount > 0),
  currency char(3) not null default 'PEN' check (currency ~ '^[A-Z]{3}$'),
  payment_status public.payment_status not null default 'pending',
  yape_operation_code text,
  payer_phone text check (payer_phone is null or payer_phone ~ '^\\+?[1-9][0-9]{6,14}$'),
  proof_storage_bucket text not null default 'payment-proofs',
  proof_storage_path text,
  submitted_at timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  verification_note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (method, yape_operation_code)
);

create index if not exists candidate_payments_candidate_idx
  on public.candidate_payments (candidate_id, payment_status, created_at desc);

comment on table public.candidate_payments is
  'Registro de cobros. El comprobante se guarda de forma privada en Supabase Storage, no como base64 dentro de la tabla.';

-- -----------------------------------------------------------------------------
-- QR Y OPERACIÓN ADMINISTRATIVA
-- -----------------------------------------------------------------------------
create table if not exists public.candidate_qr_codes (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.candidate_profiles(id) on delete cascade,
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  qr_storage_bucket text not null default 'cv-qr-codes',
  qr_storage_path text,
  is_active boolean not null default true,
  generated_at timestamptz not null default now(),
  last_downloaded_at timestamptz,
  revoked_at timestamptz,
  check (char_length(token) >= 24)
);

create index if not exists candidate_qr_codes_active_token_idx
  on public.candidate_qr_codes (token)
  where is_active and revoked_at is null;

create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid references public.candidate_profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  body text,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists admin_notifications_unread_idx
  on public.admin_notifications (is_read, created_at desc)
  where not is_read;

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  candidate_id uuid references public.candidate_profiles(id) on delete set null,
  event_type text not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_events_candidate_idx
  on public.audit_events (candidate_id, created_at desc);

-- -----------------------------------------------------------------------------
-- FUNCIONES INTERNAS DE AUTORIZACIÓN
-- -----------------------------------------------------------------------------
create or replace function private.owns_candidate(p_candidate_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.candidate_profiles cp
    where cp.id = p_candidate_id
      and cp.owner_user_id = (select auth.uid())
  );
$$;

create or replace function private.is_staff(p_allowed_roles public.staff_role[] default null)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.staff_roles sr
    where sr.user_id = (select auth.uid())
      and sr.is_active
      and (p_allowed_roles is null or sr.role = any(p_allowed_roles))
  );
$$;

revoke all on function private.owns_candidate(uuid) from public;
revoke all on function private.is_staff(public.staff_role[]) from public;
grant execute on function private.owns_candidate(uuid) to authenticated;
grant execute on function private.is_staff(public.staff_role[]) to authenticated;

-- -----------------------------------------------------------------------------
-- FUNCIONES Y TRIGGERS DEL FLUJO
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.create_default_qr_and_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.candidate_qr_codes (candidate_id)
  values (new.id)
  on conflict (candidate_id) do nothing;

  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (
    new.id,
    'candidate_registered',
    'Nuevo registro de currículo virtual',
    coalesce(new.display_name, new.first_name || ' ' || new.last_name) || ' completó el registro inicial.'
  );

  insert into public.audit_events (actor_user_id, candidate_id, event_type, new_data)
  values (
    new.owner_user_id,
    new.id,
    'candidate_created',
    jsonb_build_object('status', new.status)
  );

  return new;
end;
$$;

create or replace function public.audit_candidate_status_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status is distinct from old.status then
    insert into public.audit_events (actor_user_id, candidate_id, event_type, old_data, new_data)
    values (
      auth.uid(),
      new.id,
      'candidate_status_changed',
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

-- El postulante solo puede enviar su propio perfil; la función protege la columna status.
create or replace function public.submit_candidate_profile(p_candidate_id uuid)
returns public.candidate_status
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_status public.candidate_status;
begin
  if not private.owns_candidate(p_candidate_id) then
    raise exception 'No tiene permiso para enviar este currículo';
  end if;

  select status into v_status
  from public.candidate_profiles
  where id = p_candidate_id
  for update;

  if v_status not in ('draft', 'payment_pending', 'rejected') then
    raise exception 'El currículo no puede enviarse desde el estado %', v_status;
  end if;

  if not exists (
    select 1
    from public.candidate_profiles cp
    where cp.id = p_candidate_id
      and cp.accepts_terms_at is not null
      and cp.allows_publication_at is not null
      and coalesce(cp.professional_summary, '') <> ''
  ) then
    raise exception 'Debe aceptar los términos, autorizar la publicación y completar el perfil profesional';
  end if;

  if not exists (
    select 1 from public.candidate_payments p
    where p.candidate_id = p_candidate_id
      and p.payment_status = 'pending'
  ) then
    raise exception 'Debe registrar un pago pendiente antes de enviar el currículo';
  end if;

  update public.candidate_profiles
  set status = 'payment_pending', submitted_at = now()
  where id = p_candidate_id;

  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (
    p_candidate_id,
    'payment_pending',
    'Pago pendiente por validar',
    'El registro fue enviado y requiere validación de pago.'
  );

  return 'payment_pending';
end;
$$;

-- El equipo de finanzas valida Yape y habilita la revisión editorial.
create or replace function public.verify_candidate_payment(
  p_payment_id uuid,
  p_is_paid boolean,
  p_verification_note text default null
)
returns public.payment_status
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_candidate_id uuid;
  v_result public.payment_status;
begin
  if not private.is_staff(array['admin', 'finance']::public.staff_role[]) then
    raise exception 'Solo finanzas o administración puede validar pagos';
  end if;

  select candidate_id into v_candidate_id
  from public.candidate_payments
  where id = p_payment_id
  for update;

  if v_candidate_id is null then
    raise exception 'Pago no encontrado';
  end if;

  v_result := case when p_is_paid then 'paid'::public.payment_status else 'rejected'::public.payment_status end;

  update public.candidate_payments
  set payment_status = v_result,
      verified_at = now(),
      verified_by = auth.uid(),
      verification_note = p_verification_note
  where id = p_payment_id;

  update public.candidate_profiles
  set status = case when p_is_paid then 'under_review'::public.candidate_status else 'payment_pending'::public.candidate_status end
  where id = v_candidate_id
    and status in ('draft', 'payment_pending', 'under_review');

  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (
    v_candidate_id,
    case when p_is_paid then 'payment_verified' else 'payment_rejected' end,
    case when p_is_paid then 'Pago validado' else 'Pago rechazado' end,
    coalesce(p_verification_note, '')
  );

  return v_result;
end;
$$;

-- Un revisor aprueba o rechaza después de comprobar los datos del CV.
create or replace function public.review_candidate_profile(
  p_candidate_id uuid,
  p_is_approved boolean,
  p_internal_note text default null
)
returns public.candidate_status
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.is_staff(array['admin', 'reviewer']::public.staff_role[]) then
    raise exception 'Solo revisión o administración puede aprobar perfiles';
  end if;

  if not exists (
    select 1 from public.candidate_payments p
    where p.candidate_id = p_candidate_id and p.payment_status = 'paid'
  ) then
    raise exception 'No se puede aprobar un currículo sin pago validado';
  end if;

  update public.candidate_profiles
  set status = case when p_is_approved then 'approved'::public.candidate_status else 'rejected'::public.candidate_status end,
      approved_at = case when p_is_approved then now() else null end,
      approved_by = case when p_is_approved then auth.uid() else null end,
      internal_notes = p_internal_note
  where id = p_candidate_id
    and status in ('under_review', 'approved', 'rejected');

  if not found then
    raise exception 'El currículo no está listo para revisión o no existe';
  end if;

  return case when p_is_approved then 'approved'::public.candidate_status else 'rejected'::public.candidate_status end;
end;
$$;

-- Publicar exige aprobación, pago confirmado y un fondo Cloudflare listo y público.
create or replace function public.publish_candidate_profile(p_candidate_id uuid)
returns public.candidate_status
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo publicación o administración puede publicar perfiles';
  end if;

  if not exists (
    select 1 from public.candidate_profiles cp
    where cp.id = p_candidate_id and cp.status = 'approved'
  ) then
    raise exception 'El currículo debe estar aprobado antes de publicarse';
  end if;

  if not exists (
    select 1 from public.candidate_payments p
    where p.candidate_id = p_candidate_id and p.payment_status = 'paid'
  ) then
    raise exception 'El pago debe estar validado antes de publicarse';
  end if;

  if not exists (
    select 1 from public.candidate_media m
    where m.candidate_id = p_candidate_id
      and m.is_background
      and m.media_status = 'ready'
      and m.visibility = 'public'
      and m.playback_url is not null
  ) then
    raise exception 'Debe asignarse un video o imagen de fondo público y listo en Cloudflare';
  end if;

  update public.candidate_profiles
  set status = 'published', published_at = now(), published_by = auth.uid()
  where id = p_candidate_id;

  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (p_candidate_id, 'candidate_published', 'Currículo publicado', 'El QR ya muestra el contenido público.');

  return 'published';
end;
$$;

create or replace function public.unpublish_candidate_profile(p_candidate_id uuid, p_reason text default null)
returns public.candidate_status
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo publicación o administración puede despublicar perfiles';
  end if;

  update public.candidate_profiles
  set status = 'approved', internal_notes = coalesce(p_reason, internal_notes)
  where id = p_candidate_id and status = 'published';

  if not found then
    raise exception 'No existe un currículo publicado con ese identificador';
  end if;

  return 'approved';
end;
$$;

-- Devuelve exclusivamente la información pública. Si el QR existe pero no está
-- publicado, la web matriz debe mostrar la pantalla «En construcción».
create or replace function public.get_public_cv(p_qr_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_candidate public.candidate_profiles%rowtype;
  v_result jsonb;
begin
  select cp.*
  into v_candidate
  from public.candidate_qr_codes qr
  join public.candidate_profiles cp on cp.id = qr.candidate_id
  where qr.token = p_qr_token
    and qr.is_active
    and qr.revoked_at is null;

  if not found then
    return jsonb_build_object('state', 'not_found');
  end if;

  if v_candidate.status <> 'published'
     or (v_candidate.expires_at is not null and v_candidate.expires_at <= now()) then
    return jsonb_build_object('state', 'under_construction');
  end if;

  select jsonb_strip_nulls(
    jsonb_build_object(
      'state', 'published',
      'profile', jsonb_strip_nulls(jsonb_build_object(
        'id', v_candidate.id,
        'display_name', coalesce(v_candidate.display_name, v_candidate.first_name || ' ' || v_candidate.last_name),
        'headline', v_candidate.headline,
        'professional_summary', v_candidate.professional_summary,
        'location', case when v_candidate.show_location then concat_ws(', ', v_candidate.city, v_candidate.country_code) end,
        'email', case when v_candidate.show_email then v_candidate.email end,
        'phone', case when v_candidate.show_phone then v_candidate.phone end,
        'whatsapp_phone', case when v_candidate.show_whatsapp then v_candidate.whatsapp_phone end,
        'linkedin_url', v_candidate.linkedin_url,
        'portfolio_url', v_candidate.portfolio_url,
        'website_url', v_candidate.website_url,
        'presentation_config', v_candidate.presentation_config
      )),
      'background_media', (
        select jsonb_strip_nulls(jsonb_build_object(
          'type', m.media_type,
          'provider', m.provider,
          'playback_url', m.playback_url,
          'thumbnail_url', m.thumbnail_url,
          'duration_seconds', m.duration_seconds
        ))
        from public.candidate_media m
        where m.candidate_id = v_candidate.id
          and m.is_background
          and m.media_status = 'ready'
          and m.visibility = 'public'
        limit 1
      ),
      'experience', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'company_name', e.company_name,
          'position_title', e.position_title,
          'employment_type', e.employment_type,
          'location', e.location,
          'start_date', e.start_date,
          'end_date', e.end_date,
          'is_current', e.is_current,
          'description', e.description
        )) order by e.display_order, e.start_date desc nulls last)
        from public.candidate_experiences e
        where e.candidate_id = v_candidate.id and e.is_public
      ), '[]'::jsonb),
      'education', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'institution_name', ed.institution_name,
          'degree_or_program', ed.degree_or_program,
          'field_of_study', ed.field_of_study,
          'start_date', ed.start_date,
          'end_date', ed.end_date,
          'is_current', ed.is_current,
          'description', ed.description
        )) order by ed.display_order, ed.start_date desc nulls last)
        from public.candidate_education ed
        where ed.candidate_id = v_candidate.id and ed.is_public
      ), '[]'::jsonb),
      'questions', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'key', q.question_key,
          'question', q.question_text,
          'answer_text', a.answer_text,
          'boolean_value', a.boolean_value,
          'selected_options', coalesce((
            select jsonb_agg(o.option_label order by o.display_order)
            from public.candidate_answer_options ao
            join public.questionnaire_options o on o.id = ao.option_id
            where ao.answer_id = a.id
          ), '[]'::jsonb)
        )) order by q.display_order)
        from public.candidate_answers a
        join public.questionnaire_questions q on q.id = a.question_id
        where a.candidate_id = v_candidate.id and q.is_public
      ), '[]'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

-- Entrega al dueño del perfil el token y la URL que debe codificar en el QR.
create or replace function public.get_my_qr(p_candidate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_base_url text;
  v_qr public.candidate_qr_codes%rowtype;
begin
  if not private.owns_candidate(p_candidate_id) then
    raise exception 'No tiene permiso para consultar este QR';
  end if;

  select public_web_base_url into v_base_url from public.platform_settings where singleton;
  select * into v_qr from public.candidate_qr_codes where candidate_id = p_candidate_id and is_active and revoked_at is null;

  if not found then
    raise exception 'QR no encontrado';
  end if;

  return jsonb_build_object(
    'token', v_qr.token,
    'url', rtrim(v_base_url, '/') || '/cv.html?code=' || v_qr.token,
    'qr_storage_bucket', v_qr.qr_storage_bucket,
    'qr_storage_path', v_qr.qr_storage_path
  );
end;
$$;

revoke all on function public.submit_candidate_profile(uuid) from public;
revoke all on function public.verify_candidate_payment(uuid, boolean, text) from public;
revoke all on function public.review_candidate_profile(uuid, boolean, text) from public;
revoke all on function public.publish_candidate_profile(uuid) from public;
revoke all on function public.unpublish_candidate_profile(uuid, text) from public;
revoke all on function public.get_my_qr(uuid) from public;
grant execute on function public.submit_candidate_profile(uuid) to authenticated;
grant execute on function public.verify_candidate_payment(uuid, boolean, text) to authenticated;
grant execute on function public.review_candidate_profile(uuid, boolean, text) to authenticated;
grant execute on function public.publish_candidate_profile(uuid) to authenticated;
grant execute on function public.unpublish_candidate_profile(uuid, text) to authenticated;
grant execute on function public.get_my_qr(uuid) to authenticated;
grant execute on function public.get_public_cv(text) to anon, authenticated;

-- Triggers de actualización, QR y auditoría.
drop trigger if exists set_platform_settings_updated_at on public.platform_settings;
create trigger set_platform_settings_updated_at before update on public.platform_settings
for each row execute function public.set_updated_at();

drop trigger if exists set_candidate_profiles_updated_at on public.candidate_profiles;
create trigger set_candidate_profiles_updated_at before update on public.candidate_profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_candidate_experiences_updated_at on public.candidate_experiences;
create trigger set_candidate_experiences_updated_at before update on public.candidate_experiences
for each row execute function public.set_updated_at();

drop trigger if exists set_candidate_education_updated_at on public.candidate_education;
create trigger set_candidate_education_updated_at before update on public.candidate_education
for each row execute function public.set_updated_at();

drop trigger if exists set_questionnaire_questions_updated_at on public.questionnaire_questions;
create trigger set_questionnaire_questions_updated_at before update on public.questionnaire_questions
for each row execute function public.set_updated_at();

drop trigger if exists set_candidate_answers_updated_at on public.candidate_answers;
create trigger set_candidate_answers_updated_at before update on public.candidate_answers
for each row execute function public.set_updated_at();

drop trigger if exists set_candidate_payments_updated_at on public.candidate_payments;
create trigger set_candidate_payments_updated_at before update on public.candidate_payments
for each row execute function public.set_updated_at();

drop trigger if exists candidate_profile_after_insert on public.candidate_profiles;
create trigger candidate_profile_after_insert after insert on public.candidate_profiles
for each row execute function public.create_default_qr_and_notification();

drop trigger if exists candidate_profile_status_audit on public.candidate_profiles;
create trigger candidate_profile_status_audit after update of status on public.candidate_profiles
for each row execute function public.audit_candidate_status_change();

-- -----------------------------------------------------------------------------
-- SEGURIDAD: RLS Y PRIVILEGIOS
-- El frontend solo recibe la clave pública/anon. No use service_role en GitHub.
-- -----------------------------------------------------------------------------
alter table public.platform_settings enable row level security;
alter table public.staff_roles enable row level security;
alter table public.candidate_profiles enable row level security;
alter table public.candidate_experiences enable row level security;
alter table public.candidate_education enable row level security;
alter table public.questionnaire_questions enable row level security;
alter table public.questionnaire_options enable row level security;
alter table public.candidate_answers enable row level security;
alter table public.candidate_answer_options enable row level security;
alter table public.candidate_media enable row level security;
alter table public.candidate_payments enable row level security;
alter table public.candidate_qr_codes enable row level security;
alter table public.admin_notifications enable row level security;
alter table public.audit_events enable row level security;

-- Se revocan los privilegios generales antes de conceder las operaciones mínimas.
revoke all on all tables in schema public from anon, authenticated;

-- El visitante no debe consultar tablas directamente: usa solo get_public_cv(token).
-- El usuario autenticado crea y edita únicamente datos de su propio perfil.
grant select, insert on public.candidate_profiles to authenticated;
grant update (
  first_name, last_name, display_name, headline, professional_summary, city, country_code,
  email, phone, whatsapp_phone, linkedin_url, portfolio_url, website_url,
  show_email, show_phone, show_whatsapp, show_location, public_handle,
  presentation_config, accepts_terms_at, allows_publication_at, registration_source
) on public.candidate_profiles to authenticated;
grant delete on public.candidate_profiles to authenticated;

grant select, insert, update, delete on public.candidate_experiences to authenticated;
grant select, insert, update, delete on public.candidate_education to authenticated;
grant select on public.questionnaire_questions, public.questionnaire_options to authenticated;
grant select, insert, update, delete on public.candidate_answers, public.candidate_answer_options to authenticated;
grant select on public.candidate_media to authenticated;
grant select, insert on public.candidate_payments to authenticated;
grant select on public.candidate_qr_codes to authenticated;

-- El equipo interno usa RPC seguras para los cambios sensibles.
grant select on public.admin_notifications, public.audit_events to authenticated;
grant update (is_read, read_at) on public.admin_notifications to authenticated;
grant select, insert, update, delete on public.staff_roles, public.platform_settings, public.candidate_media to authenticated;

-- Políticas de candidate_profiles.
drop policy if exists candidate_profiles_select_own_or_staff on public.candidate_profiles;
create policy candidate_profiles_select_own_or_staff on public.candidate_profiles
for select to authenticated
using (owner_user_id = (select auth.uid()) or (select private.is_staff()));

drop policy if exists candidate_profiles_insert_own_draft on public.candidate_profiles;
create policy candidate_profiles_insert_own_draft on public.candidate_profiles
for insert to authenticated
with check (
  owner_user_id = (select auth.uid())
  and status = 'draft'
  and approved_at is null and approved_by is null
  and published_at is null and published_by is null
  and internal_notes is null
);

drop policy if exists candidate_profiles_update_own on public.candidate_profiles;
create policy candidate_profiles_update_own on public.candidate_profiles
for update to authenticated
using (owner_user_id = (select auth.uid()))
with check (owner_user_id = (select auth.uid()));

drop policy if exists candidate_profiles_delete_own_draft on public.candidate_profiles;
create policy candidate_profiles_delete_own_draft on public.candidate_profiles
for delete to authenticated
using (owner_user_id = (select auth.uid()) and status = 'draft');

-- Políticas para experiencia y estudios.
drop policy if exists candidate_experiences_owner_or_staff on public.candidate_experiences;
create policy candidate_experiences_owner_or_staff on public.candidate_experiences
for all to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()))
with check ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

drop policy if exists candidate_education_owner_or_staff on public.candidate_education;
create policy candidate_education_owner_or_staff on public.candidate_education
for all to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()))
with check ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

-- Preguntas editables solo por administración; todos los candidatos autenticados las leen.
drop policy if exists questions_read_active on public.questionnaire_questions;
create policy questions_read_active on public.questionnaire_questions
for select to authenticated
using (is_active or (select private.is_staff()));

drop policy if exists questions_staff_manage on public.questionnaire_questions;
create policy questions_staff_manage on public.questionnaire_questions
for all to authenticated
using ((select private.is_staff(array['admin']::public.staff_role[])))
with check ((select private.is_staff(array['admin']::public.staff_role[])));

drop policy if exists options_read_active on public.questionnaire_options;
create policy options_read_active on public.questionnaire_options
for select to authenticated
using (is_active or (select private.is_staff()));

drop policy if exists options_staff_manage on public.questionnaire_options;
create policy options_staff_manage on public.questionnaire_options
for all to authenticated
using ((select private.is_staff(array['admin']::public.staff_role[])))
with check ((select private.is_staff(array['admin']::public.staff_role[])));

-- Respuestas privadas del dueño o personal interno.
drop policy if exists candidate_answers_owner_or_staff on public.candidate_answers;
create policy candidate_answers_owner_or_staff on public.candidate_answers
for all to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()))
with check ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

drop policy if exists candidate_answer_options_owner_or_staff on public.candidate_answer_options;
create policy candidate_answer_options_owner_or_staff on public.candidate_answer_options
for all to authenticated
using (
  exists (
    select 1 from public.candidate_answers a
    where a.id = answer_id
      and ((select private.owns_candidate(a.candidate_id)) or (select private.is_staff()))
  )
)
with check (
  exists (
    select 1 from public.candidate_answers a
    where a.id = answer_id
      and ((select private.owns_candidate(a.candidate_id)) or (select private.is_staff()))
  )
);

-- El video/imagen lo agrega el equipo, y el candidato solo puede verlo en su perfil.
drop policy if exists candidate_media_select_owner_or_staff on public.candidate_media;
create policy candidate_media_select_owner_or_staff on public.candidate_media
for select to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

drop policy if exists candidate_media_staff_manage on public.candidate_media;
create policy candidate_media_staff_manage on public.candidate_media
for all to authenticated
using ((select private.is_staff(array['admin', 'publisher']::public.staff_role[])))
with check ((select private.is_staff(array['admin', 'publisher']::public.staff_role[])));

-- Pagos privados: el usuario registra y ve los suyos; finanzas/administración valida por RPC.
drop policy if exists candidate_payments_select_owner_or_staff on public.candidate_payments;
create policy candidate_payments_select_owner_or_staff on public.candidate_payments
for select to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

drop policy if exists candidate_payments_insert_own_pending on public.candidate_payments;
create policy candidate_payments_insert_own_pending on public.candidate_payments
for insert to authenticated
with check (
  (select private.owns_candidate(candidate_id))
  and payment_status = 'pending'
  and verified_at is null and verified_by is null
);

-- QR privado para su dueño y personal. El QR público se resuelve por función.
drop policy if exists candidate_qr_codes_select_owner_or_staff on public.candidate_qr_codes;
create policy candidate_qr_codes_select_owner_or_staff on public.candidate_qr_codes
for select to authenticated
using ((select private.owns_candidate(candidate_id)) or (select private.is_staff()));

-- Datos internos.
drop policy if exists staff_roles_admin_manage on public.staff_roles;
create policy staff_roles_admin_manage on public.staff_roles
for all to authenticated
using ((select private.is_staff(array['admin']::public.staff_role[])))
with check ((select private.is_staff(array['admin']::public.staff_role[])));

drop policy if exists platform_settings_admin_manage on public.platform_settings;
create policy platform_settings_admin_manage on public.platform_settings
for all to authenticated
using ((select private.is_staff(array['admin']::public.staff_role[])))
with check ((select private.is_staff(array['admin']::public.staff_role[])));

drop policy if exists admin_notifications_staff_only on public.admin_notifications;
create policy admin_notifications_staff_only on public.admin_notifications
for select to authenticated
using ((select private.is_staff()));

drop policy if exists admin_notifications_staff_update on public.admin_notifications;
create policy admin_notifications_staff_update on public.admin_notifications
for update to authenticated
using ((select private.is_staff()))
with check ((select private.is_staff()));

drop policy if exists audit_events_staff_only on public.audit_events;
create policy audit_events_staff_only on public.audit_events
for select to authenticated
using ((select private.is_staff()));

-- -----------------------------------------------------------------------------
-- SUPABASE STORAGE
-- QR y comprobantes permanecen dentro de Supabase Storage, ambos privados.
-- La web puede generar el PNG/SVG localmente y opcionalmente guardarlo en cv-qr-codes.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('payment-proofs', 'payment-proofs', false, 10485760, array['image/jpeg', 'image/png', 'application/pdf']),
  ('cv-qr-codes', 'cv-qr-codes', false, 2097152, array['image/png', 'image/svg+xml'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- La ruta debe comenzar por el candidate_id, por ejemplo:
-- payment-proofs/<candidate_id>/voucher.png
-- cv-qr-codes/<candidate_id>/qr.png
drop policy if exists payment_proofs_owner_select on storage.objects;
create policy payment_proofs_owner_select on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and exists (
    select 1 from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists payment_proofs_owner_insert on storage.objects;
create policy payment_proofs_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'payment-proofs'
  and exists (
    select 1 from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists payment_proofs_finance_select on storage.objects;
create policy payment_proofs_finance_select on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (select private.is_staff(array['admin', 'finance']::public.staff_role[]))
);

drop policy if exists qr_codes_owner_select on storage.objects;
create policy qr_codes_owner_select on storage.objects
for select to authenticated
using (
  bucket_id = 'cv-qr-codes'
  and exists (
    select 1 from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists qr_codes_owner_insert on storage.objects;
create policy qr_codes_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'cv-qr-codes'
  and exists (
    select 1 from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists qr_codes_staff_select on storage.objects;
create policy qr_codes_staff_select on storage.objects
for select to authenticated
using (
  bucket_id = 'cv-qr-codes'
  and (select private.is_staff())
);

-- Avisos en tiempo real para que el panel administrativo reciba el alta.
-- Se valida antes para que la migración no falle si ya estaba incluida.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'admin_notifications'
  ) then
    alter publication supabase_realtime add table public.admin_notifications;
  end if;
end $$;

commit;

-- =============================================================================
-- INICIALIZACIÓN POSTERIOR (EJECUTAR UNA VEZ, EDITANDO LOS VALORES):
--
-- 1) URL pública de GitHub Pages / dominio:
-- update public.platform_settings
-- set public_web_base_url = 'https://cartasinteractivas-jpg.github.io/cvirtual';
--
-- 2) Primer administrador:
-- insert into public.staff_roles (user_id, role)
-- values ('UUID-DE-auth.users-DEL-ADMINISTRADOR', 'admin');
--
-- 3) Ejemplo de preguntas predefinidas:
-- insert into public.questionnaire_questions
--   (question_key, question_text, input_type, is_required, is_public, display_order)
-- values
--   ('availability', '¿Cuál es tu disponibilidad?', 'single_choice', true, true, 10),
--   ('skills', '¿Cuáles son tus principales habilidades?', 'multiple_choice', false, true, 20),
--   ('about_you', 'Cuéntanos brevemente sobre ti', 'long_text', false, false, 30);
--
-- insert into public.questionnaire_options (question_id, option_value, option_label, display_order)
-- select id, 'immediate', 'Inmediata', 10
-- from public.questionnaire_questions where question_key = 'availability';
-- =============================================================================
