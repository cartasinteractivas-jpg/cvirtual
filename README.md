# CVirtual — Registro de perfiles

Esta aplicación es la primera web del sistema CVirtual. Está diseñada para que una persona complete su perfil profesional desde el teléfono, adjunte una foto, video de presentación y comprobante Yape. Después de validar el pago y publicar el perfil, la segunda aplicación mostrará el contenido a través de un QR único.

## Qué incluye

| Área | Implementación |
|---|---|
| Experiencia de bienvenida | Video vertical con escenas de oficina, construcción y limpieza; incluye alternativa de imágenes y botón **Saltar presentación**. |
| Formulario | Seis etapas: perfil, experiencia, estudios, archivos, pago Yape y revisión. |
| Archivos | Previsualización local de foto, video y comprobante antes de enviar. |
| Supabase | Registro de perfiles, estudios, experiencias, pago, comprobante y envío a revisión mediante el esquema SQL entregado. |
| Supabase Storage | Foto, video y comprobante se cargan a buckets privados con políticas RLS por candidato. |
| Responsive | Diseñado para uso móvil y ampliado a dos paneles en pantallas grandes. |

## Requisitos previos en Supabase

Ejecuta en este orden `001_cv_virtual_schema.sql`, `002_supabase_storage_media.sql`, `003_cvirtual_adm.sql` y `004_dni_client_access.sql`. Este registro no usa **Anonymous Sign-Ins** ni una Edge Function. En **Authentication → Providers → Email**, mantén Email activado y desactiva **Confirm email** para que el acceso por DNI se cree de forma inmediata.

## Configuración pública

Edita el archivo `client/public/config.js`. El proyecto ya contiene la URL y clave `anon` del proyecto de Supabase que compartiste. La clave `anon` es pública por diseño; aun así, la seguridad real depende de que RLS siga habilitado.

```js
window.CVIRTUAL_CONFIG = {
  supabaseUrl: "https://wpzddhmllctdsiuxenss.supabase.co",
  supabaseAnonKey: "TU_CLAVE_ANON",
  assetsBaseUrl: "./assets/",
  registrationEndpoint: "https://TU-PROYECTO.supabase.co/functions/v1/register-profile",
};
```

La web usa la URL y la clave `anon` de Supabase para crear el acceso por DNI y guardar foto, video y comprobante en los buckets privados. No necesita Cloudflare ni credenciales privadas.

## Supabase Storage para foto y video

El parche SQL crea tres buckets **privados**. Al crear el acceso por DNI, la sesión autenticada del nuevo cliente carga los archivos dentro de su propia carpeta; los buckets se descargan solamente con autorización o URL firmada temporal.[1]

| Bucket | Archivo | Ruta de carga |
|---|---|---|
| `candidate-photos` | Foto de perfil | `<candidate_id>/photo-<fecha>-<archivo>` |
| `candidate-videos` | Video de presentación | `<candidate_id>/video-<fecha>-<archivo>` |
| `payment-proofs` | Captura o PDF de Yape | `<candidate_id>/yape-<fecha>-<archivo>` |

La aplicación registra cada foto o video en `candidate_media` con estado `uploading` y visibilidad `private`. Desde el panel administrativo se llama a `publish_candidate_media(media_id, true|false)` tras aprobar el perfil; esa función cambia el estado a `ready/public`. La página del QR puede solicitar una URL firmada con duración breve para mostrar solo los medios publicados.

## Ejecución local

```bash
pnpm install
pnpm dev
```

Para validar el proyecto antes de subirlo:

```bash
pnpm check
pnpm build
```

## Publicación en GitHub Pages

Este proyecto usa Vite. Configura `base` en `vite.config.ts` con el nombre del repositorio, por ejemplo `/cvirtual/`, y genera la carpeta de producción.

```bash
pnpm build
```

Publica la carpeta generada por Vite, normalmente `dist/public`, en GitHub Pages. Mantén `config.js` dentro del contenido publicado si quieres cambiar la clave pública o la URL de Supabase sin recompilar el proyecto.

Antes de compilar para GitHub Pages, crea `client/public/assets/`, copia allí los cuatro recursos adjuntos —video de bienvenida, tres imágenes de escenas laborales y símbolo de marca— y cambia `assetsBaseUrl` a `"./assets/"` en `client/public/config.js`. Así el repositorio no depende de rutas de la vista previa.

## Flujo de la persona registrada

| Paso | Resultado |
|---:|---|
| 1 | Escribe el DNI de 8 dígitos; el resto de datos del currículo queda opcional y editable después. |
| 2 | Adjunta foto, video de presentación y captura Yape solo si los tiene disponibles. |
| 3 | La sesión creada por Supabase registra `candidate_profiles`, historial, estudios, pago inicial de S/ 40 y QR. |
| 4 | La foto, video y comprobante se guardan de forma privada en Supabase Storage. |
| 5 | Se entrega una clave temporal de una sola visualización; el DNI es el usuario para entrar a `cvirtual_adm`. |
| 6 | El QR se crea en la base y permanece **En construcción** hasta la aprobación y publicación. |

## Archivos principales

| Archivo | Uso |
|---|---|
| `client/src/pages/Home.tsx` | Pantalla de inscripción y lógica de envío. |
| `client/src/index.css` | Estilo visual móvil, animaciones y diseño responsive. |
| `client/src/lib/supabase.ts` | Cliente público de Supabase y configuración de recursos. |
| `client/public/config.js` | Configuración pública editable de Supabase y recursos visuales. |
| `supabase/002_supabase_storage_media.sql` | Parche SQL para buckets privados, RLS y publicación de foto/video. |
| `supabase/004_dni_client_access.sql` | DNI único como identificador de cliente. |
| `ideas.md` | Dirección de diseño adoptada. |

## Restricciones importantes

No subas al repositorio una clave `service_role`, token R2, API token de Stream ni contraseña de base de datos. El DNI identifica al cliente, pero no se usa como contraseña: la aplicación entrega una clave temporal aleatoria que el cliente cambia al entrar a su panel.

## Referencias

[1]: https://supabase.com/docs/guides/storage/security/access-control "Supabase — Storage Access Control"
