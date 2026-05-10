# 📚 LectorSync — Herramientas Compartidas del Equipo

Configuración de 4 herramientas inteligentes para acelerar el desarrollo de **LectorSync**: app multiplataforma de lectura sincronizada (Flutter 3+ · Node.js · PostgreSQL).

---

## 🎯 4 Herramientas para el equipo

| Herramienta | Comando | Usa para |
|---|---|---|
| **Superpowers** | `/plan` | Descomponer features complejas (motor sync, multi-plataforma) |
| **Everything Claude Code** | `/code-review`, `/security` | Revisar Dart/Flutter, Node.js, APIs |
| **UI UX Pro Max** | `/design` | UI para 5 plataformas (iOS, Android, macOS, Windows, Linux) |
| **claude-mem** | `/mem-search` | Recordar decisiones de arquitectura de LectorSync |

---

## 🚀 Ejemplos de uso para LectorSync

### Feature: Motor de sincronización
```
/plan: Motor de sincronización palabra-por-palabra
       - Latencia < 100ms
       - Múltiples proveedores TTS (ElevenLabs, Azure, Google)
       - Persistencia de highlights
       - Tests de latencia
```
→ Superpowers divide en subtareas paralelas

### Revisar código Flutter
```
/code-review: Mi BLoC de sincronización de audio
/security: Mi autenticación y encriptación de datos
```
→ Everything Claude Code valida SOLID, Clean Architecture, seguridad

### Diseñar UI multi-plataforma
```
/design: Reader interface para iOS + Android con dark mode sensorial
```
→ UI UX Pro Max genera código consistente para 5 plataformas

### Recordar decisiones
```
/mem-search: Por qué usamos BLoC en lugar de Riverpod
/mem-search: Cómo manejamos la sincronización entre plataformas
/mem-search: Arquitectura del motor de TTS
```
→ claude-mem recuerda ADRs del proyecto

---

## 📁 Estructura

```
.claude/
├── README.md                    ← Este archivo
├── CLAUDE.md                    ← Guía completa
├── settings.json                ← Config compartida
├── .gitignore
│
└── docs/
    ├── GETTING-STARTED.md       ← Para nuevos devs
    ├── DECISIONS.md             ← ADRs de LectorSync
    ├── ARCHITECTURE.md          ← Diagrama de sistemas
    ├── FLUTTER-GUIDELINES.md    ← Estándares Flutter/Dart
    └── BACKEND-API.md           ← Documentación Node.js/PostgreSQL
```

---

## 👥 Rol de cada desarrollador

### Flutter Developer (iOS, Android, macOS, Linux)
```
/plan: Feature nueva para UI/UX
/code-review: Mi widget/BLoC antes de PR
/design: Componentes nuevos
/mem-search: Cómo lo hizo alguien en otra plataforma
```

### Node.js / Backend Developer
```
/plan: Feature nueva en API o DB
/code-review: Mi endpoint o modelo
/security: Autenticación y autorizacion
/mem-search: Cómo manejamos la sincronización
```

### UI/UX Designer
```
/design: Nuevas pantallas o flujos
/mem-search: Decisiones de diseño previas
/plan: Refinamiento de UX
```

### DevOps / QA
```
/code-review: Pipeline CI/CD
/security: Vulnerabilidades antes de deploy
/plan: Estrategia de testing
```

---

## 🔧 Stack específico de LectorSync

### Frontend (Flutter)
- **Lenguaje**: Dart
- **Framework**: Flutter 3+
- **Estado**: BLoC (Clean Architecture)
- **Motor de sync**: Custom sync engine (< 100ms latencia)

**Comandos relevantes**:
```
/code-review: Mi BLoC
/design: Nuevo widget
/plan: Feature multi-plataforma
```

### Backend (Node.js)
- **Lenguaje**: TypeScript / JavaScript
- **Framework**: Express / NestJS
- **BD**: PostgreSQL
- **TTS**: ElevenLabs, Azure, Google

**Comandos relevantes**:
```
/code-review: Mi endpoint
/security: Mi autenticación
/plan: Feature en API
```

### Multi-plataforma
- **iOS**: Native Swift cuando sea necesario
- **Android**: Native Kotlin cuando sea necesario
- **macOS/Windows/Linux**: Flutter nativo

**Comandos relevantes**:
```
/design: Consistencia entre plataformas
/mem-search: Cómo lo hizo otro en otra plataforma
```

---

## 🎯 Flujo de trabajo típico

### Morning: Planificar
```
/plan: Feature - Soporte para múltiples voces por personaje
       incluir: análisis NLP, fallback, tests, UX
```

### Midday: Implementar
```
Escribes en Flutter + Node.js...
/code-review: Mi SyncEngine
/code-review: Mi endpoint de personalidades
```

### Afternoon: Diseño
```
/design: Reader interface para mostrar personajes
```

### Evening: Contexto
```
/mem-search: Cómo manejamos la sincronización
/mem-search: Decisiones de arquitectura
```

---

## 📚 Documentación específica

### Si trabajas con Flutter:
```bash
cat .claude/docs/FLUTTER-GUIDELINES.md
/code-review: Mi BLoC
```

### Si trabajas con Node.js/Backend:
```bash
cat .claude/docs/BACKEND-API.md
/code-review: Mi endpoint
```

### Si necesitas entender el sync:
```bash
cat .claude/docs/DECISIONS.md          # ADRs
/mem-search: Motor de sincronización
```

### Si eres nuevo:
```bash
cat .claude/docs/GETTING-STARTED.md
cat lector_sync_project_definition.md
/mem-search: Arquitectura general
```

---

## 🚀 Primeros pasos

### Si eres nuevo en LectorSync:

**Day 1:**
```bash
# 5 minutos
cat .claude/docs/GETTING-STARTED.md

# 15 minutos
cat lector_sync_project_definition.md

# 30 minutos
/mem-search: Arquitectura general
/mem-search: Motor de sincronización
```

**Day 2:**
```bash
# Lee guidelines específicas
cat .claude/docs/FLUTTER-GUIDELINES.md    # si Flutter
cat .claude/docs/BACKEND-API.md           # si Backend

# Revisa decisiones
cat .claude/docs/DECISIONS.md
```

**Day 3:**
```bash
# Haz tu primer PR
/plan: Feature pequeña para aprender
/code-review: Tu código
# git push
```

### Si ya conoces LectorSync:

```
/plan: Feature que necesitas
/code-review: Código antes de PR
/mem-search: Recordar decisiones previas
```

---

## 💡 Tips para máximo beneficio

### Antes de empezar una feature:
```
/plan: [feature]
```
Te ahorra horas de diseño mental.

### Antes de hacer PR:
```
/code-review: Mi código
```
Catch bugs de seguridad, testing, patterns.

### Antes de crear UI:
```
/design: [descripción]
```
UI consistente entre 5 plataformas.

### Cuando necesitas contexto:
```
/mem-search: [qué buscas]
```
Aprende de decisiones previas.

---

## 🔐 Privacidad

### Se sincroniza en git:
✅ Configuración
✅ Documentación
✅ Decisiones (ADRs)
✅ Guidelines

### NO se sincroniza:
❌ `.mem/` — Conversaciones privadas
❌ `.env` — Credenciales
❌ `.cache/` — Cache local

---

## 🆘 Soporte

### Las herramientas no funcionan
```bash
bash ~/.claude/verify-tools.sh
bash ~/.claude/setup-tools.sh
```

### Necesito ayuda con Flutter
```
/code-review: Mi código
/mem-search: Cómo hicieron esto antes
```

### Necesito ayuda con Node.js
```
/code-review: Mi endpoint
/security: Estoy seguro?
```

### Necesito recordar algo
```
/mem-search: [qué buscas]
```

---

## 📞 Equipo

- **Líder técnico**: Ver `.claude/docs/DECISIONS.md`
- **Documentación**: Dentro de `.claude/docs/`
- **Dudas**: Usa `/mem-search` o pregunta

---

## 🎯 Siguientes pasos

1. Lee `docs/GETTING-STARTED.md` (5 min)
2. Lee `docs/DECISIONS.md` — ADRs de LectorSync (10 min)
3. Lee guidelines específicos según tu rol
4. Abre Claude Code: `/plan help`
5. ¡Haz tu primer PR con `/code-review`!

---

**LectorSync usa herramientas inteligentes para desarrollar más rápido, en 5 plataformas, manteniendo sincronización < 100ms.** 🚀

*Última actualización: 2026-04-21*
