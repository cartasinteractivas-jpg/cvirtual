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

Ejecuta primero la migración `001_cv_virtual_schema.sql` que se entregó anteriormente y, después, `supabase/002_supabase_storage_media.sql` incluido en este proyecto. Luego, en **Authentication → Providers**, habilita **Anonymous Sign-Ins**. La web crea una sesión anónima persistente para que la persona pueda registrar solo su propio perfil, sin mostrar una pantalla de inicio de sesión.

> Las políticas RLS de la base permiten que cada persona anónima cree y gestione únicamente los datos relacionados con su propio registro. La clave `service_role` jamás debe estar en este repositorio ni en GitHub Pages.

## Configuración pública

Edita el archivo `client/public/config.js`. El proyecto ya contiene la URL y clave `anon` del proyecto de Supabase que compartiste. La clave `anon` es pública por diseño; aun así, la seguridad real depende de que RLS siga habilitado.

```js
window.CVIRTUAL_CONFIG = {
  supabaseUrl: "https://wpzddhmllctdsiuxenss.supabase.co",
  supabaseAnonKey: "TU_CLAVE_ANON",
  assetsBaseUrl: "./assets/",
};
```

La web usa solamente la URL y la clave `anon` de Supabase. No necesitas una URL de Worker ni credenciales de Cloudflare para guardar la foto, el video y el comprobante.

## Supabase Storage para foto y video

El parche SQL crea tres buckets **privados**. La web carga los archivos directamente con la sesión anónima de Supabase y las políticas verifican que el primer segmento de la ruta sea el `candidate_id` del propio usuario. Supabase Storage exige políticas RLS explícitas para permitir cargas; los buckets privados solo se descargan con autorización o URL firmada temporal.[1]

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
| 1 | Completa datos personales, experiencia y formación. |
| 2 | Adjunta foto, video de presentación y captura de pago Yape. |
| 3 | La web crea `candidate_profiles`, historial laboral, estudios y `candidate_payments`. |
| 4 | La foto, video y comprobante se guardan de forma privada en Supabase Storage, cada uno dentro de la carpeta del candidato. |
| 5 | Se ejecuta `submit_candidate_profile`; el estado pasa a `payment_pending` y el panel recibe una alerta. |
| 6 | El QR se crea en la base. Hasta aprobar y publicar, muestra **En construcción**. |

## Archivos principales

| Archivo | Uso |
|---|---|
| `client/src/pages/Home.tsx` | Pantalla de inscripción y lógica de envío. |
| `client/src/index.css` | Estilo visual móvil, animaciones y diseño responsive. |
| `client/src/lib/supabase.ts` | Cliente Supabase y sesión anónima. |
| `client/public/config.js` | Configuración pública editable de Supabase y recursos visuales. |
| `supabase/002_supabase_storage_media.sql` | Parche SQL para buckets privados, RLS y publicación de foto/video. |
| `ideas.md` | Dirección de diseño adoptada. |

## Restricciones importantes

No subas al repositorio una clave `service_role`, token R2, API token de Stream ni contraseña de base de datos. El código está preparado para que la sesión pública se limite por políticas RLS en Supabase Storage.

## Referencias

[1]: https://supabase.com/docs/guides/storage/security/access-control "Supabase — Storage Access Control"
