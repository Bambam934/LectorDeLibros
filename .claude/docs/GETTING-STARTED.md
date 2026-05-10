# 🚀 Empezar con LectorSync — 5 minutos

## Bienvenido a LectorSync 🎧📚

Aplicación multiplataforma de lectura sincronizada con audio de alta calidad.

---

## Primeros 5 minutos

### 1. Clonar y abrir
```bash
git clone <LectorSync>
cd LectorDeLibros
claude              # Abre Claude Code
```

### 2. Probar las herramientas (1 minuto)
```
/plan help              ← Descomposición multi-agente
/code-review help       ← Revisión inteligente
/design help            ← UI profesional
/mem-search help        ← Memoria del proyecto
```

### 3. Entender el proyecto (4 minutos)
```bash
# Lee esto primero
cat lector_sync_project_definition.md | head -100

# Luego esto
cat .claude/docs/DECISIONS.md
```

---

## Primeros 2 días

### Día 1: Setup y contexto

**Morning (30 min)**:
```bash
# Lee estos archivos
cat lector_sync_project_definition.md      # Visión general
cat .claude/docs/GETTING-STARTED.md         # Este archivo
cat .claude/README.md                       # Herramientas disponibles
```

**Midday (30 min)**:
```
/mem-search: Arquitectura general de LectorSync
/mem-search: Motor de sincronización
/mem-search: Stack tecnológico (Flutter, Node.js, PostgreSQL)
```

**Afternoon (30 min)**:
```bash
# Lee según tu rol:

# Si eres Flutter Dev:
cat .claude/docs/FLUTTER-GUIDELINES.md

# Si eres Backend Dev:
cat .claude/docs/BACKEND-API.md

# Si eres Designer:
cat .claude/docs/DECISIONS.md | grep -i "design"
```

### Día 2: Primer PR

**Morning (1 hora)**:
```
/plan: Feature pequeña para aprender
       Ej: Agregar logo en splash screen
       Ej: Agregar campo en Settings
```

**Afternoon (2 horas)**:
Implementas el código...

**Evening (1 hora)**:
```
/code-review: Mi código
# Fix feedback

git add . && git commit -m "feat: ..." && git push
```

---

## Estructura del proyecto

```
LectorDeLibros/
├── .claude/                    ← Configuración compartida (tú estás aquí)
│   ├── README.md              ← Resumen de herramientas
│   ├── CLAUDE.md              ← Guía completa
│   ├── settings.json          ← Config para todos
│   └── docs/
│       ├── GETTING-STARTED.md ← Este archivo
│       ├── DECISIONS.md       ← Decisiones técnicas
│       ├── FLUTTER-GUIDELINES.md
│       ├── BACKEND-API.md
│       └── ARCHITECTURE.md
│
├── lib/                        ← Código Flutter
│   ├── presentation/           ← BLoCs, Pages, Widgets
│   ├── domain/                 ← Entities, UseCases, Repositories
│   └── data/                   ← DataSources, Models, Adapters
│
├── backend/                    ← Código Node.js
│   ├── src/
│   ├── tests/
│   └── package.json
│
└── lector_sync_project_definition.md  ← Blueprint completo del proyecto
```

---

## Comandos que usarás constantemente

### Cuando empiezas una feature
```
/plan: Feature - [nombre con detalles]

Ej: /plan: Feature - Soporte para múltiples voces por personaje
           - NLP para detectar diálogos
           - Adaptador para ElevenLabs, Azure, Google
           - UI para seleccionar voz
           - Tests de sincronización < 100ms
           - Documentación OpenAPI
```

### Cuando necesitas revisar código
```
/code-review: Mi [componente/endpoint/función]

Ej: /code-review: Mi SyncEngine BLoC
/code-review: Mi endpoint de personalidades
```

### Cuando necesitas seguridad
```
/security: Mi [código/endpoint]

Ej: /security: Mi autenticación JWT
/security: Estoy guardando credenciales correctamente?
```

### Cuando necesitas diseño
```
/design: [descripción UI]

Ej: /design: Reader interface para iOS con dark mode sensorial
```

### Cuando necesitas contexto
```
/mem-search: [qué buscas]

Ej: /mem-search: Cómo implementaron el motor de sync
/mem-search: Por qué usamos BLoC
```

---

## Tips importantes

### ✅ DO
- Usa `/plan` para features complejas (te ahorra horas)
- Usa `/code-review` antes de cada PR (catch bugs)
- Usa `/mem-search` para aprender del código anterior (reutiliza)
- Usa `/design` para UI consistente (5 plataformas)

### ❌ DON'T
- No hagas PR sin `/code-review`
- No olvides `/mem-search` — alguien ya lo hizo
- No cambies arquitectura sin `/plan`
- No repitas bugs — busca en memoria primero

---

## Problemas comunes

### "¿Cómo hago X en LectorSync?"
```
/mem-search: Cómo se implementa X en este proyecto
```

### "¿Estoy cumpliendo los estándares?"
```
/code-review: Mi código
```

### "¿Es seguro mi código?"
```
/code-review: Mi código
/security: [si maneja datos sensibles]
```

### "¿Debo usar este patrón?"
```
/mem-search: Cómo manejamos [cosa similar]
```

### "¿Cómo agrego soporte para nueva plataforma?"
```
/mem-search: Cómo agregaron soporte para [plataforma]
/plan: Feature - Soporte para [nueva plataforma]
```

---

## Roles en el equipo

### 🎨 Flutter Developer (UI/UX en 5 plataformas)
```
Herramientas que usarás más:
/design         → Componentes visuales consistentes
/code-review    → BLoCs, Widgets, Providers
/mem-search     → Cómo lo hicieron en otra plataforma

Objetivo: IOS, Android, macOS, Windows, Linux en sync
```

### 🔧 Backend Developer (Node.js, API, DB)
```
Herramientas que usarás más:
/plan           → Arquiteción de features
/code-review    → Endpoints, middlewares, validación
/security       → Autenticación, encriptación
/mem-search     → Patrones de DB y API

Objetivo: API rápida, segura, con sincronización < 100ms
```

### 🎵 Audio/Sync Engineer (Motor de sincronización)
```
Herramientas que usarás más:
/plan           → Optimización de latencia
/code-review    → Código de sync
/mem-search     → Cómo optimizaron antes

Objetivo: Latencia < 100ms en todas las plataformas
```

### 🎨 Designer (UI/UX)
```
Herramientas que usarás más:
/design         → Interfaces para todas las plataformas
/mem-search     → Decisiones de diseño previas
/plan           → Refinamiento de flujos

Objetivo: UX sensorial, accesible, en 5 plataformas
```

### 🧪 QA / DevOps
```
Herramientas que usarás más:
/code-review    → Tests, CI/CD, coverage
/security       → Vulnerabilidades antes de deploy
/plan           → Estrategia de testing

Objetivo: 80%+ cobertura, cero vulnerabilidades
```

---

## Siguiente paso

1. ✓ Leíste esto
2. ✓ Entiendes que hay 4 herramientas
3. → **Abre Claude Code y corre**: `/plan help`

---

**Bienvenido a LectorSync. El equipo usa herramientas inteligentes para desarrollar rápido en 5 plataformas.** 🚀

*¿Listo? Empieza ahora con `/plan: Feature pequeña para aprender`*
