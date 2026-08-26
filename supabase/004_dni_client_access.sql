-- DNI como identificador de cliente y acceso temporal seguro.
-- Ejecutar después de 001, 002 y 003.
begin;

alter table public.candidate_profiles
  add column if not exists dni char(8);

create unique index if not exists candidate_profiles_dni_unique_idx
  on public.candidate_profiles (dni)
  where dni is not null;

alter table public.candidate_profiles
  drop constraint if exists candidate_profiles_dni_format;
alter table public.candidate_profiles
  add constraint candidate_profiles_dni_format
  check (dni is null or dni ~ '^[0-9]{8}$');

commit;
