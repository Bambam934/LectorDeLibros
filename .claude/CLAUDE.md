# 🎧 LectorSync — Enhanced Tools Suite

Herramientas inteligentes configuradas para el equipo de **LectorSync**: aplicación multiplataforma de lectura sincronizada con audio de alta calidad.

**Stack**: Flutter 3+ · Dart · Node.js · TypeScript · PostgreSQL

---

## 📚 Las 4 Herramientas

### 1. Superpowers — Piloto automático con subagentes

**Comando**: `/plan`

**Ideal para LectorSync**:
- Features complejas multi-plataforma
- Motor de sincronización (latencia < 100ms)
- Integración de múltiples TTS providers
- Arquitectura de soporte para 5 plataformas

**Ejemplo**:
```
/plan: Feature - Soporte para diálogos con voces por personaje
       Requirements:
       - NLP para detectar diálogos
       - Fallback a voz única
       - Tests de latencia
       - UI para seleccionar personajes
       - Persistencia en DB
```

**Resultado**: 
- Superpowers divide en subtareas
- Subagente A: NLP implementation (Dart)
- Subagente B: Backend API (Node.js)
- Subagente C: UI (Flutter)
- Subagente D: Tests y QA
- Todos trabajan en paralelo

---

### 2. Everything Claude Code — 28 Agentes especializados

**Comandos**: `/code-review`, `/security`, `/tdd`, `/verify`

**Para LectorSync**:
- Revisar Dart/Flutter code (SOLID, Clean Architecture)
- Revisar Node.js/TypeScript code (APIs, validación)
- Análisis de seguridad: autenticación, encriptación de datos
- Testing: 80%+ cobertura required

**Ejemplos**:
```
# Revisar BLoC de sincronización
/code-review: Mi SyncEngine BLoC
/security: Mi autenticación con JWT

# Revisar API
/code-review: Mi endpoint de personalidades de voz
/security: Estoy manejando datos sensibles correctamente?

# TDD
/tdd: Feature - Motor de sync con < 100ms latencia
```

**Lo que valida**:
- ✅ SOLID principles
- ✅ Clean Architecture
- ✅ Security (102 reglas)
- ✅ Testing coverage
- ✅ Performance (especialmente sync timing)

---

### 3. UI UX Pro Max — Diseño profesional

**Comando**: `/design`

**Para LectorSync**:
- Interfaces para 5 plataformas (iOS, Android, macOS, Windows, Linux)
- Reader interface (sincronización visual palabra-por-palabra)
- Dark mode con ambientación sensorial
- Diseño consistente cross-platform

**Ejemplos**:
```
# Reader interface
/design: Reader screen para iOS/Android con:
         - Highlight palabra-por-palabra
         - Dark mode sensorial
         - Controles de audio
         - Configuración de voz

# Library screen
/design: Library screen con:
         - Búsqueda y filtros
         - Sincronización visual
         - Covers de libros

# Settings
/design: Settings panel para:
         - Selección de voz/personalidad
         - Velocidad de lectura
         - Tema (light/dark)
         - Sincronización de dispositivos
```

**Resultado**:
- UI profesional y consistente
- Código React/Vue/Svelte (adaptable a Flutter widgets)
- 67 estilos + 161 reglas UX
- Diseño responsive para todas las plataformas

---

### 4. claude-mem — Memoria permanente

**Comandos**: `/mem-search`, `/mem-view`, `/mem-stats`

**Para LectorSync**:
- Recordar ADRs (Architecture Decision Records)
- Recordar decisiones de diseño
- Recordar patrones implementados
- Compartir contexto entre developers

**Ejemplos**:
```
# Entender decisiones previas
/mem-search: Por qué usamos BLoC en lugar de Riverpod
/mem-search: Arquitectura del motor de sincronización
/mem-search: Cómo manejamos la persistencia de estado

# Encontrar patrones
/mem-search: Cómo implementaron la autenticación
/mem-search: Cómo manejan la sincronización multi-dispositivo
/mem-search: Cómo decidieron el schema de PostgreSQL

# Aprender del pasado
/mem-search: Qué problemas encontramos con latencia
/mem-search: Cómo optimizamos el motor de sync
```

**Resultado**:
- Equipo alineado en decisiones
- Evita duplicar trabajo
- Documentación viva del proyecto

---

## 🚀 Flujo de trabajo para LectorSync

### Morning: Planificar feature
```
/plan: Feature - [descripción completa]
```

### Midday: Implementar
```
Escribes Flutter + Node.js...

# Si Flutter:
/code-review: Mi BLoC de [feature]

# Si Backend:
/code-review: Mi endpoint de [feature]
/security: Estoy manejando datos sensibles correctamente?
```

### Afternoon: Diseño
```
/design: UI para [feature]
```

### Evening: Contexto
```
/mem-search: Cómo manejamos [cosa similar] antes
/mem-search: Decisiones que tomamos en [área]
```

---

## 👥 Guía por rol

### Flutter Developer (iOS, Android, macOS, Linux)
```
/plan              → Features con UX multi-plataforma
/code-review       → Mi BLoC, mi widget, mi provider
/design            → Componentes nuevos
/mem-search        → Cómo implementaron en otra plataforma
```

**Tips**:
- Usa `/code-review` para validar SOLID
- Usa `/mem-search` para reutilizar widgets/BLoCs
- Usa `/design` para UI consistente

### Node.js / Backend Developer
```
/plan              → Features en API o DB
/code-review       → Mi endpoint, mi middleware
/security          → Autenticación, encriptación
/mem-search        → Cómo hicieron en otra API
```

**Tips**:
- Usa `/security` en endpoints de pagos/auth
- Usa `/code-review` para validar validaciones
- Usa `/mem-search` para patrones de DB

### UI/UX Designer
```
/design            → Nuevas pantallas
/mem-search        → Decisiones de diseño previas
/plan              → Refinamiento de UX
```

**Tips**:
- Usa `/design` para consistency
- Usa `/mem-search` para entender decisiones
- Colabora con Flutter developers

### QA / DevOps
```
/plan              → Estrategia de testing
/code-review       → Pipeline CI/CD, tests
/security          → Vulnerabilidades
```

**Tips**:
- Usa `/security` en features críticas
- Usa `/code-review` para coverage analysis
- Usa `/plan` para test strategy

---

## 💡 Tips específicos para LectorSync

### Para el motor de sincronización
```
/plan: Optimización del motor de sync

Features importantes:
- Latencia < 100ms (crítico)
- Múltiples TTS providers
- Fallback automático
- Tests de rendimiento

/mem-search: Cómo optimizamos latencia antes
/code-review: Mi implementación de sync
```

### Para multi-plataforma
```
/design: Feature para todas las plataformas
/mem-search: Cómo hicieron en iOS/Android/macOS
/code-review: Mi código es compatible con [plataforma]
```

### Para TTS integration
```
/plan: Soporte para nuevo TTS provider
/code-review: Mi adaptador de TTS
/security: Estoy manejando APIs keys correctamente
```

### Para la experiencia sensorial
```
/design: UI con ambientación sensorial
/plan: Sonido de página, vibración háptica
/mem-search: Cómo manejamos haptics en otras plataformas
```

---

## 🔐 Privacidad en LectorSync

### Se sincroniza (público):
✅ Configuración de herramientas
✅ Decisiones arquitectónicas (ADRs)
✅ Guidelines de Flutter/Node.js
✅ Documentación del proyecto

### NO se sincroniza:
❌ `.mem/` — Conversaciones privadas
❌ `.env` — API keys, credenciales
❌ Datos de usuarios (GDPR compliance)
❌ Cache local

---

## 📊 Beneficios para LectorSync

```
Sin herramientas:
- Feature multi-plataforma: 2 semanas
- Bugs de seguridad: detectados en producción
- Inconsistencia de UX: entre plataformas
- Contexto: se olvida entre developers

Con herramientas:
- Feature multi-plataforma: 3-5 días (4x)
- Bugs de seguridad: detectados antes (102 reglas)
- Consistencia de UX: automática
- Contexto: recordado automáticamente

Ahorro: 80% en time-to-market
Ganancia: 90% mejor calidad
```

---

## 🎯 Comandos rápida referencia

| Necesitas | Comando |
|---|---|
| Planificar feature | `/plan: [descripción]` |
| Revisar código | `/code-review: [mi código]` |
| Validar seguridad | `/security: [mi código/endpoint]` |
| Diseñar UI | `/design: [descripción UI]` |
| Recordar decisión | `/mem-search: [qué buscas]` |
| Ver tu memoria | `/mem-view` |
| Estadísticas | `/mem-stats` |

---

## 📚 Documentación

```
.claude/docs/
├── GETTING-STARTED.md          ← Primer día
├── DECISIONS.md                ← ADRs de LectorSync
├── FLUTTER-GUIDELINES.md       ← Estándares Dart/Flutter
├── BACKEND-API.md              ← Node.js/PostgreSQL
└── ARCHITECTURE.md             ← Diagrama de sistemas
```

---

## 🚀 Empezar ahora

1. Lee este archivo (ya lo hiciste ✓)
2. Lee `.claude/docs/GETTING-STARTED.md`
3. Abre Claude Code: `/plan help`
4. Prueba: `/code-review: test`
5. ¡Haz tu feature con `/plan`!

---

**LectorSync: Lectura sincronizada en 5 plataformas con latencia < 100ms.** 🎧📚

*Última actualización: 2026-04-21*
