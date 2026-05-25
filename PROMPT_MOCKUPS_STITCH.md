# Prompt para Google Stitch — Mockups LectorSync

> Copiar TODO el contenido debajo de la linea y pegarlo en Stitch.

---

Diseña los mockups completos de una aplicación móvil llamada "LectorSync" para smartphones (iPhone 15 Pro, 393x852px). La app es un lector de libros digitales con síntesis de voz sincronizada y resaltado palabra por palabra. Diseña exactamente 6 pantallas conectadas con navegación funcional. Usa un estilo moderno, limpio y minimalista tipo Material Design / Ionic Framework.

## PALETA DE COLORES (obligatoria en todas las pantallas)

- Primary: #4F46E5 (índigo/violeta) — headers, botones principales, íconos activos, enlaces
- Primary Dark: #3730A3 — textos resaltados, estados pressed
- Primary Light: #E0E7FF — fondos de badges, fondos de cards secundarias
- Accent/Warning: #F59E0B (ámbar) — palabra resaltada durante TTS, chips activos, indicadores
- Accent Light: #FEF3C7 — fondo de la palabra activa
- Success: #10B981 — barras de progreso de lectura, porcentajes
- Danger: #EF4444 — botón eliminar, alertas
- Background: #F8FAFC (gris muy claro) — fondo general de toda la app
- Surface: #FFFFFF — cards, modales, listas
- Text Primary: #1E293B (casi negro) — títulos, texto de lectura
- Text Secondary: #64748B (gris medio) — subtítulos, metadata
- Dark: #1E1E2E — toolbar del reader, footer TTS
- Border: #E2E8F0 — separadores, bordes de cards

## TIPOGRAFÍA

- Font family: SF Pro Display / Inter (sans-serif)
- Títulos de pantalla: 20px, bold, #1E293B
- Subtítulos: 14px, regular, #64748B
- Texto de lectura: 18px, regular, #1E293B, line-height 1.8
- Badges: 11px, semibold, uppercase
- Botones: 16px, semibold

---

## PANTALLA 1: INICIO DE SESIÓN (pantalla inicial de la app)

Fondo: #F8FAFC completo, sin header/toolbar.

Contenido centrado verticalmente en la pantalla:

1. **Sección logo** (centrada, parte superior del centro):
   - Ícono de libro abierto con ondas de audio saliendo (outline, 64px, color #4F46E5)
   - Debajo: texto "LectorSync" en 28px, font-weight 800, color #1E293B
   - Debajo: subtítulo "Lectura sincronizada con audio" en 14px, color #64748B

2. **Card de formulario** (fondo blanco #FFFFFF, border-radius 12px, sombra sutil, ancho 100% con padding horizontal 20px):
   - Header de card: "Iniciar sesión" en 18px, bold, #1E293B
   - Campo "Correo electrónico" — input con label flotante, borde gris #E2E8F0, border-radius 8px, ícono de sobre a la izquierda en #64748B
   - Campo "Contraseña" — input con label flotante, tipo password con ícono de ojo para mostrar/ocultar a la derecha, borde gris #E2E8F0
   - Botón "Iniciar sesión" — ancho completo, fondo sólido #4F46E5, texto blanco 16px semibold, border-radius 8px, 48px de alto, sombra sutil
   - Debajo del botón: texto link "¿No tienes cuenta? Regístrate" en 14px, color #4F46E5, centrado, subrayado al hover

3. **Footer**: texto "EquipoEPMB02 - 4" en 12px, color #64748B, centrado, margin-top 24px

**Navegación**: El botón "Iniciar sesión" lleva a Pantalla 3 (Biblioteca). El link "Regístrate" lleva a Pantalla 2 (Registro).

---

## PANTALLA 2: REGISTRO (accesible desde el link de la Pantalla 1)

Mismo layout y diseño visual que Pantalla 1 (mismo logo, mismo fondo, mismo footer) pero con estas diferencias dentro de la card:

1. Header de card: "Crear cuenta" (en vez de "Iniciar sesión"), 18px, bold, #1E293B
2. **Tres campos** (en vez de dos):
   - Campo "Nombre completo" — input con label flotante, ícono de persona (outline) a la izquierda en #64748B, borde #E2E8F0, border-radius 8px
   - Campo "Correo electrónico" — idéntico al de Pantalla 1
   - Campo "Contraseña" — idéntico al de Pantalla 1
3. Botón principal: "Registrarse" (fondo sólido #4F46E5, texto blanco, ancho completo, 48px alto)
4. Texto link inferior: "¿Ya tienes cuenta? Inicia sesión" en 14px, color #4F46E5, centrado

El logo LectorSync, subtítulo y footer EquipoEPMB02-4 permanecen idénticos a Pantalla 1.

**Navegación**: "Registrarse" lleva a Pantalla 3 (Biblioteca). "Inicia sesión" vuelve a Pantalla 1.

---

## PANTALLA 3: BIBLIOTECA PERSONAL (pantalla principal después de autenticarse)

**Header/Toolbar superior** (fondo sólido #4F46E5, texto blanco):
- Título: "Mi Biblioteca" en 20px, bold, blanco, alineado a la izquierda
- Lado derecho: dos íconos blancos (outline, 24px):
  - Ícono de "+" dentro de un círculo — para importar/agregar libro
  - Ícono de engranaje (gear/settings) — para ir a Configuración (Pantalla 6)

**Segunda toolbar** (misma franja #4F46E5, inmediatamente debajo del título):
- Barra de búsqueda (searchbar) con fondo blanco semitransparente (rgba(255,255,255,0.15)), texto placeholder "Buscar libros..." en blanco semitransparente, ícono de lupa blanca a la izquierda, border-radius 8px, height 40px

**Contenido** (fondo #F8FAFC, scroll vertical con padding 8px):

Mostrar exactamente 4 libros en formato de lista vertical (ion-list), cada libro es un item rectangular con:

**Libro 1:**
- Thumbnail izquierdo (60x80px, border-radius 6px): portada de libro con tonos azules/violetas, imagen artística de un paisaje nocturno con estrellas y mariposas amarillas
- Contenido a la derecha del thumbnail:
  - Título: "Cien Años de Soledad" en 16px, font-weight 600, color #1E293B
  - Autor: "Gabriel García Márquez" en 14px, color #64748B
  - Fila de metadata: Badge "EPUB" (fondo #E0E7FF, texto #4F46E5, border-radius 999px, font-size 11px, padding 2px 10px) + texto "25 capítulos" en 12px, color #94A3B8, margin-left 8px
  - Barra de progreso: 65% llena, color #10B981 (verde), height 4px, border-radius 2px, fondo track #E2E8F0
  - Texto "65% leído" en 11px, color #10B981, margin-top 2px
- Flecha chevron derecha (>) en color #CBD5E1, indicando que es tocable

**Libro 2:**
- Thumbnail: portada con tonos rojos/naranjas cálidos, ilustración de un pequeño príncipe en un asteroide
- Título: "El Principito" — Autor: "Antoine de Saint-Exupéry"
- Badge "PDF" (fondo #E0E7FF, texto #4F46E5) — "12 capítulos"
- Barra de progreso: 30% llena, color #10B981
- "30% leído" en #10B981

**Libro 3:**
- Thumbnail: portada con tonos marrones/sepia, ilustración de un caballero con armadura
- Título: "Don Quijote de la Mancha" — Autor: "Miguel de Cervantes"
- Badge "EPUB" — "126 capítulos"
- Barra de progreso: 10% llena, color #10B981
- "10% leído"

**Libro 4:**
- Thumbnail: rectángulo placeholder gris claro #F1F5F9 con ícono de libro outline en #94A3B8 centrado (este libro no tiene portada)
- Título: "Notas de Clase" — Autor: (sin autor, no mostrar la línea de autor)
- Badge "TXT" — "3 capítulos"
- Sin barra de progreso (libro recién agregado, 0%)

**Interacciones**: Deslizar cualquier libro hacia la izquierda revela un botón rojo #EF4444 con ícono de basura (trash) blanco y texto "Eliminar".

**Navegación**: Tocar cualquier libro lleva a Pantalla 4 (Vista del Libro). El ícono de engranaje lleva a Pantalla 6 (Configuración).

---

## PANTALLA 4: VISTA DEL LIBRO (detalle del libro seleccionado)

**Header/Toolbar superior** (fondo sólido #4F46E5, texto blanco):
- Lado izquierdo: flecha de retroceso (<) blanca para volver a la Biblioteca
- Centro: título "Cien Años de Soledad" en 17px, blanco, font-weight 600

**Contenido** (fondo #F8FAFC):

1. **Sección superior — Portada e información** (fondo blanco #FFFFFF, padding 24px, border-bottom 1px #E2E8F0):
   - Portada del libro centrada: imagen rectangular 120x170px, border-radius 8px, sombra media (0 4px 12px rgba(0,0,0,0.15)), la misma portada azul/violeta con estrellas y mariposas de Pantalla 3
   - Debajo de la portada (centrado):
     - Título: "Cien Años de Soledad" en 22px, bold, #1E293B, centrado
     - Autor: "Gabriel García Márquez" en 15px, #64748B, centrado
     - Fila de badges (centrada, gap 8px):
       - Badge "EPUB" (fondo #E0E7FF, texto #4F46E5, border-radius 999px)
       - Badge "25 capítulos" (fondo #F1F5F9, texto #64748B, border-radius 999px)
       - Badge "45.230 palabras" (fondo #F1F5F9, texto #64748B, border-radius 999px)
   - Barra de progreso general: 65% llena, color #10B981, height 6px, border-radius 3px, ancho completo
   - Texto "65% completado" en 13px, #10B981, centrado, margin-top 4px

2. **Botón principal — Continuar lectura** (margin 16px horizontal):
   - Botón ancho completo, fondo sólido #4F46E5, texto blanco "Continuar lectura" 16px semibold, border-radius 8px, height 48px, ícono de play pequeño a la izquierda del texto

3. **Sección — Tabla de contenidos** (fondo blanco #FFFFFF, margin-top 12px):
   - Header: "Tabla de contenidos" en 16px, bold, #1E293B, padding 16px, con borde inferior #E2E8F0
   - Lista de capítulos (8 items):
     - Cada capítulo muestra: número del capítulo (círculo 28px, fondo #E0E7FF, texto #4F46E5, centrado) + título + conteo de palabras a la derecha en gris
     - Capítulo 1: "La estirpe" — "2.450 palabras"
     - Capítulo 2: "Los gitanos" — "3.120 palabras"
     - **Capítulo 3: "El gitano"** — "1.890 palabras" — este item tiene un indicador de punto verde #10B981 (8px) a la izquierda indicando "último leído", y texto "Último leído" en 11px #10B981 debajo del título
     - Capítulo 4: "El laboratorio" — "2.780 palabras"
     - Capítulo 5: "La peste del insomnio" — "3.540 palabras"
     - Capítulo 6 a 8: similares, con separadores #E2E8F0 entre cada item

**Navegación**: La flecha de retroceso vuelve a Pantalla 3 (Biblioteca). El botón "Continuar lectura" y tocar cualquier capítulo lleva a Pantalla 5 (Lector Digital).

---

## PANTALLA 5: LECTOR DIGITAL (pantalla principal de lectura con TTS)

**Header/Toolbar superior** (fondo sólido #1E1E2E oscuro, texto blanco):
- Lado izquierdo: flecha de retroceso (<) blanca + ícono de lista/hamburger (tres líneas horizontales, 22px) blanco para mostrar la tabla de contenidos
- Centro: título "Capítulo 3: El Gitano" en 15px, blanco, font-weight 500, truncado con ellipsis si es muy largo
- Lado derecho: dos botones de cambio de tamaño de fuente:
  - Letra "A" pequeña (13px, color blanco, opacity 0.7) — para reducir fuente
  - Letra "A" grande (21px, color blanco, font-weight bold) — para aumentar fuente

**Contenido principal** (fondo blanco #FFFFFF, padding 20px horizontal, 16px superior, scroll vertical):

- Título del capítulo: "Capítulo 3: El Gitano" centrado, 22px, font-weight 700, color #4F46E5, margin-bottom 24px

- **Párrafo 1** del texto del libro (simulado, en español): mostrar aproximadamente 8 líneas de texto literario. El texto se ve en 18px, color #1E293B, line-height 1.8, text-align justify, font-family serif.

  Contenido del párrafo: "Muchos años después, frente al pelotón de fusilamiento, el coronel Aureliano Buendía había de recordar aquella tarde remota en que su padre lo llevó a conocer el hielo. Macondo era entonces una aldea de veinte casas de barro y cañabrava construidas a la orilla de un río de aguas diáfanas que se precipitaban por un lecho de piedras pulidas, blancas y enormes como huevos prehistóricos."

  **MUY IMPORTANTE — Resaltado de palabra activa TTS**: La palabra "entonces" (la 25ava palabra aproximadamente) debe estar visualmente resaltada con: fondo sólido #F59E0B (ámbar/amarillo), texto color #FFFFFF (blanco), padding 2px 6px, border-radius 4px, font-weight 600. Esto simula que el motor de Text-to-Speech está leyendo exactamente esa palabra en ese instante. TODAS las demás palabras del párrafo tienen estilo normal (#1E293B sin fondo).

- **Párrafo 2** (después de un espacio de 16px): 4-5 líneas más de texto literario normal sin ninguna palabra resaltada. Texto simulado adicional sobre la historia.

- **Navegación entre capítulos** (al final del contenido, después de 32px de espacio, con borde superior 1px #E2E8F0):
  - Dos botones outline alineados horizontalmente con justify-content space-between:
    - Izquierda: ícono chevron-left + "Anterior" (outline, borde 1px #4F46E5, texto #4F46E5, border-radius 8px, padding 10px 20px)
    - Derecha: "Siguiente" + ícono chevron-right (outline, borde 1px #4F46E5, texto #4F46E5, border-radius 8px, padding 10px 20px)

**Footer/Barra de controles TTS** (fija/sticky en la parte inferior de la pantalla, fondo sólido #1E1E2E, height 64px, padding horizontal 16px):

Fila horizontal centrada con los siguientes controles de audio, todos alineados en una línea:

- Botón Stop: ícono cuadrado de stop (outline), color blanco, sin fondo, 24px
- **Botón Play/Pause (protagonista)**: círculo sólido #4F46E5 con 50px de diámetro, centrado, ícono de PAUSA (dos barras verticales ❚❚) blanco adentro de 20px, porque en este mockup el TTS está activo reproduciendo el audio. Este botón debe ser el más grande y prominente del footer.
- Botón Skip Forward: ícono de skip next (>>|), color blanco, sin fondo, 24px
- Separador visual: línea vertical 1px #374151, height 28px, margin 0 8px
- Tres chips de velocidad alineados a la derecha, en fila horizontal, gap 4px:
  - "0.75x" — chip con fondo #374151 (gris oscuro), texto #9CA3AF (gris claro), border-radius 999px, height 28px, font-size 11px
  - "1x" — chip con fondo #4F46E5 (primary, ACTIVO/seleccionado), texto blanco, border-radius 999px, height 28px, font-size 11px, font-weight 600
  - "1.5x" — chip con fondo #374151 (gris oscuro), texto #9CA3AF (gris claro), border-radius 999px, height 28px, font-size 11px

**Navegación**: La flecha de retroceso vuelve a Pantalla 4 (Vista del Libro). El ícono de lista/hamburger despliega un panel lateral o modal con la tabla de contenidos (similar a la sección de Pantalla 4 pero como overlay).

---

## PANTALLA 6: CONFIGURACIÓN (accesible desde el engranaje de la Biblioteca)

**Header/Toolbar superior** (fondo sólido #4F46E5, texto blanco):
- Lado izquierdo: flecha de retroceso (<) blanca para volver a Biblioteca
- Centro: título "Configuración" en 20px, bold, blanco

**Contenido** (fondo #F8FAFC, scroll vertical):

1. **Sección — Apariencia** (card blanca #FFFFFF, border-radius 12px, margin 16px, sombra sutil):
   - Header de sección: "Apariencia" en 16px, bold, #1E293B, padding 16px, con ícono de paleta de colores (outline, #4F46E5) a la izquierda
   - Item 1: "Tema oscuro" — texto 15px #1E293B a la izquierda + toggle/switch a la derecha (desactivado, track gris #E2E8F0, thumb blanco). Debajo: subtítulo "Cambiar entre tema claro y oscuro" en 13px, #64748B
   - Separador #E2E8F0
   - Item 2: "Tamaño de fuente predeterminado" — texto 15px #1E293B a la izquierda + valor "18px" a la derecha en 14px #4F46E5 bold. Debajo: slider/range horizontal (track #E2E8F0, thumb #4F46E5, rango de 12 a 32, posición actual en 18)

2. **Sección — Voz y lectura** (card blanca, margin-top 12px):
   - Header de sección: "Voz y lectura" en 16px, bold, #1E293B, con ícono de micrófono (outline, #4F46E5) a la izquierda
   - Item 1: "Voz de lectura" — texto 15px #1E293B + valor actual "Microsoft Helena" a la derecha en 14px #4F46E5, con chevron derecho (>) indicando que abre selector
   - Separador
   - Item 2: "Velocidad predeterminada" — texto 15px #1E293B + tres chips en fila a la derecha:
     - "0.75x" (fondo #F1F5F9, texto #64748B)
     - "1x" (fondo #4F46E5, texto blanco, ACTIVO)
     - "1.5x" (fondo #F1F5F9, texto #64748B)
   - Separador
   - Item 3: "Resaltado de palabra" — texto 15px #1E293B + toggle/switch a la derecha (ACTIVADO, track #4F46E5, thumb blanco). Debajo: subtítulo "Resaltar la palabra actual durante la lectura por voz" en 13px, #64748B

3. **Sección — Almacenamiento** (card blanca, margin-top 12px):
   - Header de sección: "Datos locales" en 16px, bold, #1E293B, con ícono de dispositivo/phone (outline, #4F46E5) a la izquierda
   - Item 1: "Progreso guardado" — texto 15px #1E293B + badge "4 libros" a la derecha (fondo #D1FAE5, texto #065F46, border-radius 999px)
   - Separador
   - Item 2: "Borrar datos locales" — texto 15px, color #EF4444 (rojo), con ícono de basura rojo a la izquierda. Debajo: subtítulo "Eliminar progreso y preferencias guardadas" en 13px, #64748B

4. **Footer informativo** (centrado, margin-top 24px, padding 20px):
   - Texto "LectorSync v1.0.0" en 13px, #94A3B8
   - Texto "EquipoEPMB02 - 4" en 12px, #94A3B8
   - Texto "Ionic + Angular + Capacitor" en 11px, #CBD5E1

**Navegación**: La flecha de retroceso vuelve a Pantalla 3 (Biblioteca).

---

## FLUJO DE NAVEGACIÓN COMPLETO

```
Pantalla 1 (Inicio de Sesión) ←→ Pantalla 2 (Registro)
              ↓ [Iniciar sesión / Registrarse]
Pantalla 3 (Biblioteca Personal)
              ↓ [Tocar un libro]        ↓ [Ícono engranaje]
Pantalla 4 (Vista del Libro)     Pantalla 6 (Configuración)
              ↓ [Continuar lectura / Tocar capítulo]
Pantalla 5 (Lector Digital con TTS activo)
              ↓ [Flecha retroceso]
Pantalla 4 (Vista del Libro)
              ↓ [Flecha retroceso]
Pantalla 3 (Biblioteca Personal)
```

## INSTRUCCIONES GENERALES DE DISEÑO

- Todas las pantallas deben tener el status bar del iPhone en la parte superior (hora centrada, íconos de señal celular, wifi y batería a la derecha, en negro o blanco según el fondo del header)
- Usar bordes redondeados consistentes: border-radius 12px en cards, 8px en inputs y botones, 999px en badges y chips
- Sombras suaves en cards y modales: box-shadow 0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.06)
- Espaciado consistente: padding 16-20px en contenido, gaps de 12-16px entre elementos
- Los íconos deben ser estilo outline/línea (NO rellenos/filled), con trazo de 1.5-2px de grosor
- El diseño debe verse como una app nativa de iOS construida con Ionic/Capacitor — componentes ion-item, ion-card, ion-toolbar reconocibles
- NO usar gradientes en ninguna pantalla, todos los fondos de toolbar son sólidos
- Mantener alta legibilidad: ratio de contraste mínimo WCAG AA (4.5:1) entre texto y fondo
- Los toggles/switches deben usar el estilo nativo de iOS (pill-shaped, track redondeado)
- La pantalla 5 (Lector) es la más importante de toda la app: asegurar que el resaltado de la palabra "entonces" en ámbar #F59E0B sea claramente visible y sea el elemento que más llame la atención del contenido
