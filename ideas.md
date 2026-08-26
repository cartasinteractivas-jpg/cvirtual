# Dirección de diseño — CVirtual Registro

## Tres aproximaciones iniciales

### 1. Cuaderno de Oficios

Una interfaz clara inspirada en fichas laborales impresas, con papeles cálidos, sellos funcionales y fotografías de oficio. Busca cercanía y confianza para personas que prefieren un registro sin lenguaje técnico.

**Probabilidad:** 0.07

### 2. Escenario de Trayectorias

Una experiencia cinematográfica con el trabajo real como protagonista: personas saludando, construyendo y cuidando espacios aparecen detrás de una capa de registro serena. Busca dignificar todos los oficios y convertir el formulario en una presentación personal.

**Probabilidad:** 0.03

### 3. Archivo Industrial Suave

Un sistema editorial de etiquetas, columnas y metadatos inspirado en expedientes de recursos humanos contemporáneos. Busca transmitir orden operativo sin caer en un panel frío o burocrático.

**Probabilidad:** 0.09

## Enfoque elegido: Escenario de Trayectorias

### Design Movement

La experiencia se inspira en el **documental editorial contemporáneo** y en interfaces de *storytelling* de servicio público: retratos cotidianos, luz natural y capas informativas precisas sobre una escena humana en movimiento.

### Core Principles

1. **El trabajo es protagonista:** el fondo audiovisual muestra ocupaciones con respeto, sin convertirlas en decoración genérica.
2. **Una tarea por momento:** el formulario se desarrolla en etapas móviles cortas, evitando una pared de campos.
3. **Claridad que acompaña:** el usuario siempre entiende su avance, qué archivo debe entregar y qué ocurrirá después.
4. **Confianza visible:** pagos, privacidad y datos se presentan con lenguaje concreto y señales de control.

### Color Philosophy

Se usa una base de carbón profundo y azul tinta para que el video conserve presencia y el texto permanezca legible. El color distintivo es el **Naranja Señal** `#F46A3A`, inspirado en chalecos, conos y herramientas de seguridad: funciona como guía de acción, no como decoración. Marfil cálido y azul niebla suavizan las secciones de formulario para crear descanso visual.

### Layout Paradigm

La interfaz se concibe como un **retrato vertical en capas**. Un escenario a pantalla completa abre la inscripción; encima, una bandeja inferior translúcida despliega cada paso. En escritorio la bandeja se desplaza lateralmente, mientras que el metraje ocupa la columna dominante. No se utiliza una cuadrícula centrada convencional.

### Signature Elements

1. **Marcadores de escena:** chips numerados que reflejan los pasos de registro como una secuencia audiovisual.
2. **Regla de encuadre:** una línea vertical naranja y una pequeña etiqueta de oficio acompañan el cambio de cada escena.
3. **Tarjetas de carga tipo claqueta:** foto, video y comprobante muestran un estado concreto, miniatura y acción de reemplazo.

### Interaction Philosophy

Las acciones deben sentirse como preparar una presentación profesional: avanzar, guardar borrador y revisar el resultado. Los controles tienen retroalimentación breve, los archivos muestran previsualización local y las opciones se eligen mediante botones amplios aptos para uso con una sola mano.

### Animation

El fondo audiovisual cambia por fundido lento cada pocos segundos; la capa de tinta se mantiene para asegurar contraste. Las etapas entran desde abajo con una traslación leve y opacidad, en menos de 280 ms. Los botones confirman la pulsación con una escala de `0.97`. Se respeta `prefers-reduced-motion`, evitando el ciclo visual y las transiciones no esenciales.

### Typography System

**DM Sans** aporta legibilidad en controles, campos y textos de ayuda. **DM Serif Display** se usa solo para titulares de escena y frases de confianza, generando una voz editorial sin perder claridad. Los títulos se alinean a la izquierda, con jerarquía contundente; el cuerpo mantiene interlineado amplio y nunca usa texto comprimido sobre el video.

### Brand Essence

**CVirtual convierte los datos de una trayectoria laboral en una presentación humana, lista para compartirse por QR.** Personalidad: **cercana, digna y clara**.

### Brand Voice

La voz es directa, respetuosa y práctica. Los titulares nombran la acción concreta; los llamados a la acción indican qué sucederá, sin promesas vacías.

> “Tu experiencia merece verse, no perderse en un papel.”

> “Sube tu comprobante y pasamos tu perfil a revisión.”

### Wordmark & Logo

El símbolo es un marco vertical abierto que sugiere una ficha de CV y un fotograma de video; una diagonal naranja atraviesa la esquina inferior como señal de avance. El logotipo combina la serif editorial para “CV” y la sans funcional para “irtual”.

### Signature Brand Color

**Naranja Señal — `#F46A3A`**.

## Style Decisions

- La primera pantalla mostrará escenas de un profesional saludando, una persona en construcción y una trabajadora de limpieza, siempre con luz natural y encuadres humanos.
- Se incluirá el control **“Saltar presentación”** tras tres segundos para omitir la secuencia de bienvenida.
- La subida de archivos en una web estática se presentará como preparación local hasta que el repositorio configure una ruta segura de carga a Cloudflare y Supabase Storage.
- La primera pantalla debe conservar siempre un marcador visible de secuencia, etiqueta de oficio y regla vertical Naranja Señal sobre el retrato.
- Los mensajes de apoyo nombran resultados concretos: perfil, archivos, comprobante, revisión y QR; se evita la confianza genérica.
- El Naranja Señal se reserva para progresión, confirmación y orientación operativa, no como decoración indiscriminada.
