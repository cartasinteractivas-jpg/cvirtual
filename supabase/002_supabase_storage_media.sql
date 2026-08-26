-- =============================================================================
-- CVIRTUAL — PARCHE 002: FOTO Y VIDEO EN SUPABASE STORAGE
-- Ejecutar DESPUÉS de 001_cv_virtual_schema.sql, una sola vez, desde SQL Editor.
--
-- Crea dos buckets privados y permite que cada usuario anónimo autenticado
-- cargue solamente archivos dentro de la carpeta de su propio candidate_id.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- BUCKETS PRIVADOS
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'candidate-photos',
    'candidate-photos',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'candidate-videos',
    'candidate-videos',
    false,
    104857600,
    array['video/mp4', 'video/webm', 'video/quicktime']
  )
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

comment on table storage.objects is
  'Los objetos de CVirtual se guardan por candidate_id y permanecen privados hasta que el perfil se publique.';

-- -----------------------------------------------------------------------------
-- VÍNCULO DEL ARCHIVO CON candidate_media
-- Se mantiene provider = external para compatibilidad con el enum de la migración inicial.
-- metadata guarda storage_provider=supabase_storage, bucket y ruta del archivo.
-- -----------------------------------------------------------------------------
drop policy if exists candidate_media_owner_insert_supabase_storage on public.candidate_media;
create policy candidate_media_owner_insert_supabase_storage
on public.candidate_media
for insert
to authenticated
with check (
  (select private.owns_candidate(candidate_id))
  and provider = 'external'
  and media_status = 'uploading'
  and visibility = 'private'
  and not is_background
  and (metadata ->> 'storage_provider') = 'supabase_storage'
  and (metadata ->> 'storage_bucket') in ('candidate-photos', 'candidate-videos')
  and (metadata ->> 'storage_path') like candidate_id::text || '/%'
);

-- -----------------------------------------------------------------------------
-- POLÍTICAS DE SUPABASE STORAGE: DUEÑO DEL PERFIL
-- Todas las rutas deben tener el formato <candidate_id>/<archivo>.
-- -----------------------------------------------------------------------------
drop policy if exists candidate_media_owner_upload on storage.objects;
create policy candidate_media_owner_upload
on storage.objects
for insert
to authenticated
with check (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and exists (
    select 1
    from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists candidate_media_owner_read on storage.objects;
create policy candidate_media_owner_read
on storage.objects
for select
to authenticated
using (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and exists (
    select 1
    from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

drop policy if exists candidate_media_owner_delete on storage.objects;
create policy candidate_media_owner_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and exists (
    select 1
    from public.candidate_profiles cp
    where cp.id::text = (storage.foldername(name))[1]
      and cp.owner_user_id = (select auth.uid())
  )
);

-- -----------------------------------------------------------------------------
-- POLÍTICAS PARA EL EQUIPO INTERNO
-- Finanzas no necesita estos archivos; revisión, publicación y administración sí.
-- -----------------------------------------------------------------------------
drop policy if exists candidate_media_staff_read on storage.objects;
create policy candidate_media_staff_read
on storage.objects
for select
to authenticated
using (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and (select private.is_staff(array['admin', 'reviewer', 'publisher']::public.staff_role[]))
);

drop policy if exists candidate_media_staff_manage_files on storage.objects;
create policy candidate_media_staff_manage_files
on storage.objects
for all
to authenticated
using (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and (select private.is_staff(array['admin', 'publisher']::public.staff_role[]))
)
with check (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and (select private.is_staff(array['admin', 'publisher']::public.staff_role[]))
);

-- -----------------------------------------------------------------------------
-- PUBLICACIÓN DE ARCHIVOS
-- Esta función solo deja visible un medio cuando el perfil ya fue aprobado.
-- El panel administrativo la llama después de comprobar foto/video.
-- -----------------------------------------------------------------------------
create or replace function public.publish_candidate_media(
  p_media_id uuid,
  p_is_background boolean default false
)
returns public.candidate_media
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_media public.candidate_media%rowtype;
begin
  if not private.is_staff(array['admin', 'publisher']::public.staff_role[]) then
    raise exception 'Solo publicación o administración puede preparar contenido multimedia';
  end if;

  select m.* into v_media
  from public.candidate_media m
  join public.candidate_profiles cp on cp.id = m.candidate_id
  where m.id = p_media_id
    and cp.status = 'approved'
    and (m.metadata ->> 'storage_provider') = 'supabase_storage'
    and (m.metadata ->> 'storage_bucket') in ('candidate-photos', 'candidate-videos')
  for update;

  if not found then
    raise exception 'El archivo no existe, no pertenece a Supabase Storage o el perfil aún no está aprobado';
  end if;

  update public.candidate_media
  set media_status = 'ready',
      visibility = 'public',
      is_background = p_is_background
  where id = p_media_id
  returning * into v_media;

  return v_media;
end;
$$;

revoke all on function public.publish_candidate_media(uuid, boolean) from public;
grant execute on function public.publish_candidate_media(uuid, boolean) to authenticated;

-- Sustituye la validación inicial de publicación para aceptar un medio de
-- Supabase Storage. Así no se exige playback_url, que solo aplica a Cloudflare.
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
    select 1
    from public.candidate_media m
    where m.candidate_id = p_candidate_id
      and m.is_background
      and m.media_status = 'ready'
      and m.visibility = 'public'
      and (
        m.playback_url is not null
        or (
          (m.metadata ->> 'storage_provider') = 'supabase_storage'
          and (m.metadata ->> 'storage_bucket') in ('candidate-photos', 'candidate-videos')
          and nullif(m.metadata ->> 'storage_path', '') is not null
        )
      )
  ) then
    raise exception 'Debe asignarse un video o imagen de fondo listo para publicar';
  end if;

  update public.candidate_profiles
  set status = 'published', published_at = now(), published_by = auth.uid()
  where id = p_candidate_id;

  insert into public.admin_notifications (candidate_id, notification_type, title, body)
  values (p_candidate_id, 'candidate_published', 'Currículo publicado', 'El QR ya muestra el contenido público.');

  return 'published';
end;
$$;

-- La web pública del QR usa esta función y luego solicita una URL firmada de
-- corta duración mediante supabase.storage.from(bucket).createSignedUrl(path, 300).
create or replace function public.get_public_cv_media(p_qr_token text)
returns table (
  media_id uuid,
  media_type public.media_type,
  storage_bucket text,
  storage_path text,
  is_background boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    m.id,
    m.media_type,
    m.metadata ->> 'storage_bucket' as storage_bucket,
    m.metadata ->> 'storage_path' as storage_path,
    m.is_background
  from public.candidate_qr_codes qr
  join public.candidate_profiles cp on cp.id = qr.candidate_id
  join public.candidate_media m on m.candidate_id = cp.id
  where qr.token = p_qr_token
    and qr.is_active
    and qr.revoked_at is null
    and cp.status = 'published'
    and (cp.expires_at is null or cp.expires_at > now())
    and m.media_status = 'ready'
    and m.visibility = 'public'
    and (m.metadata ->> 'storage_provider') = 'supabase_storage';
$$;

revoke all on function public.get_public_cv_media(text) from public;
grant execute on function public.get_public_cv_media(text) to anon, authenticated;

-- Permite crear URLs firmadas exclusivamente para archivos de perfiles ya
-- publicados. Los objetos siguen siendo privados: la URL expira en pocos minutos.
drop policy if exists candidate_media_published_signed_read on storage.objects;
create policy candidate_media_published_signed_read
on storage.objects
for select
to anon, authenticated
using (
  bucket_id in ('candidate-photos', 'candidate-videos')
  and exists (
    select 1
    from public.candidate_media m
    join public.candidate_profiles cp on cp.id = m.candidate_id
    where (m.metadata ->> 'storage_bucket') = storage.objects.bucket_id
      and (m.metadata ->> 'storage_path') = storage.objects.name
      and cp.status = 'published'
      and (cp.expires_at is null or cp.expires_at > now())
      and m.visibility = 'public'
      and m.media_status = 'ready'
      and (m.metadata ->> 'storage_provider') = 'supabase_storage'
  )
);

commit;

-- =============================================================================
-- PRUEBA OPCIONAL DESPUÉS DE REGISTRAR UNA PERSONA
-- select * from storage.objects where bucket_id in ('candidate-photos', 'candidate-videos');
-- select * from public.candidate_media order by uploaded_at desc;
-- =============================================================================
