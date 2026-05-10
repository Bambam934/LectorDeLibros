# LectorSync

> Lector de libros con Text-to-Speech y sincronización palabra-a-palabra

## Tabla de Contenidos

- [Descripción](#descripción)
- [Arquitectura](#arquitectura)
- [Tecnología](#tecnología)
- [Primeros Pasos](#primeros-pasos)
- [Seguridad](#seguridad)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [API Endpoints](#api-endpoints)
- [Configuración](#configuración)

---

## Descripción

LectorSync es una aplicación full-stack para lectura de libros con soporte para múltiples formatos (EPUB, PDF, TXT, Markdown) y Text-to-Speech con sincronización palabra-a-palabra. Incluye:

- **Importación multi-formato**: EPUB, PDF, TXT, MD
- **Text-to-Speech**: TTS del dispositivo + ElevenLabs con timestamps
- **Sincronización**: Resaltado palabra por palabra durante la lectura
- **Auto-scroll**: Desplazamiento automático al párrafo activo
- **Progreso persistente**: Guarda posición exacta de lectura
- **Layouts responsivos**: Soporte desktop y mobile

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                               │
├─────────────────────────────────────────────────────────────────┤
│  AuthCubit ──► LibraryBloc ──► ReaderBloc (TTS + Audio)          │
│       │              │                    │                       │
│  SecureStorage   RemoteLibRepo      RemoteReaderRepo             │
│       │              │                    │                       │
└───────│──────────────│────────────────────│───────────────────────┘
        │              │                    │
        ▼              ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     API Client (Dio)                             │
│  - JWT interceptor (auto-refresh)                               │
│  - Base URL: localhost:3000 / 10.0.2.2:3000                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP
┌─────────────────────────────────────────────────────────────────┐
│                    Fastify Backend                               │
├─────────────────────────────────────────────────────────────────┤
│  Routes: /api/v1/*                                              │
│    ├── Auth (register, login, refresh, logout)                  │
│    ├── Library (list, import, delete)                           │
│    └── Reader (chapters, audio, progress)                        │
│                                                                  │
│  Core:                                                           │
│    ├── Parsers (EPUB, PDF, TXT, MD)                              │
│    ├── TTS (ElevenLabs, Mock)                                   │
│    └── GLM (NVIDIA AI for text processing)                      │
│                                                                  │
│  DB: PostgreSQL via Drizzle ORM                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tecnología

### Backend

| Componente | Tecnología |
|------------|------------|
| Runtime | Node.js 22+ |
| Lenguaje | TypeScript 5.7 |
| Framework | Fastify 5.0 |
| Base de datos | PostgreSQL 16 |
| ORM | Drizzle ORM |
| Auth | @fastify/jwt (JWT) |
| Validación | Zod |
| Parsers | pdfjs-dist, adm-zip, xml2js |
| AI | OpenAI SDK (NVIDIA NIM - GLM-5.1) |
| Hash | Node.js crypto (scrypt) |

### Frontend (Flutter)

| Componente | Tecnología |
|------------|------------|
| Framework | Flutter 3.24+ |
| Estado | flutter_bloc (BLoC) |
| Navegación | go_router |
| DI | get_it |
| HTTP | Dio |
| Storage | flutter_secure_storage |
| Audio | just_audio |
| TTS | flutter_tts |

---

## Primeros Pasos

### Requisitos

- Node.js 22+
- Flutter 3.24+
- Docker Desktop (para PostgreSQL)
- npm 10+

### Instalación

```bash
# 1. Backend
cd backend
cp .env.example .env
npm install
npm run db:up
npm run db:push
npm run db:seed
npm run dev

# 2. Frontend
cd lectorsync
flutter pub get
flutter run -d chrome
```

### URLs por Defecto

| Entorno | URL |
|---------|-----|
| Backend local | http://127.0.0.1:3000 |
| Flutter Desktop | http://localhost:3000 |
| Android Emulator | http://10.0.2.2:3000 |

---

## Seguridad

### Medidas Implementadas

| Característica | Implementación |
|----------------|----------------|
| Password Hashing | scrypt con salt aleatorio (64-byte) |
| Access Token | JWT, 15 min TTL |
| Refresh Token | JWT, 30 días TTL |
| Rate Limiting | 100 req/min por cliente |
| Validación Input | Zod schemas en todos los endpoints |
| CORS | Configurado con credentials |
| Ownership Check | Verificación de propiedad en todas las operaciones |
| Secret Storage | flutter_secure_storage en móvil |

### Configuración de Producción

⚠️ **Antes de desplegar en producción**:

1. **JWT_SECRET**: Generar una clave segura de al menos 32 caracteres
   ```bash
   openssl rand -base64 32
   ```

2. **DATABASE_URL**: Usar PostgreSQL con SSL enabled

3. **CORS**: Configurar orígenes específicos
   ```typescript
   // NO USAR en producción
   origin: true  // ❌

   // USAR orígenes específicos
   origin: ['https://tu-dominio.com']  // ✅
   ```

4. **Rate Limiting**: Ajustar según necesidades

5. **HTTPS**: Desplegar detrás de un proxy con TLS

6. **API Keys**: Usar secretos de entorno (no hardcodear)
   - NVIDIA_API_KEY
   - ELEVENLABS_API_KEY

### Mejores Prácticas Recomendadas

| Prioridad | Mejora | Descripción |
|-----------|--------|-------------|
| Alta | Revocación de refresh tokens | Implementar logout real invalidando refresh tokens |
| Alta | Validación MIME estricta | Verificar tipo de archivo en upload |
| Media | Headers de seguridad | CSP, HSTS, X-Frame-Options |
| Media | Rate limit por IP | Prevenir ataques DDoS |
| Media | Logging de autenticación | Auditar intentos de login |
| Baja | Escaneo de archivos | Verificar malware en uploads |
| Baja | Almacenamiento S3 | Migrar file_key a almacenamiento cloud |

---

## Estructura del Proyecto

```
LectorDeLibros/
├── backend/                    # API Fastify + TypeScript
│   ├── src/
│   │   ├── api/v1/routes.ts    # Endpoints API v1
│   │   ├── core/
│   │   │   ├── auth.ts         # Middleware JWT
│   │   │   ├── env.ts          # Validación Zod
│   │   │   ├── glm.ts          # NVIDIA GLM-5.1
│   │   │   ├── jwt.ts          # Helpers token
│   │   │   ├── password.ts     # Hash scrypt
│   │   │   ├── parsers/        # Parsers libro
│   │   │   └── tts/            # Proveedores TTS
│   │   ├── db/
│   │   │   ├── schema.ts       # Drizzle schema
│   │   │   ├── client.ts       # Pool PostgreSQL
│   │   │   └── seed.ts         # Datos demo
│   │   ├── app.ts             # Builder Fastify
│   │   └── server.ts          # Entry point
│   ├── .env.example
│   ├── package.json
│   └── README.md
│
├── lectorsync/                 # App Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── bootstrap.dart
│   │   ├── app.dart
│   │   ├── core/
│   │   │   ├── di/             # GetIt DI
│   │   │   ├── network/        # Dio client
│   │   │   ├── router/         # GoRouter
│   │   │   ├── storage/        # Secure storage
│   │   │   ├── theme/          # Light/dark
│   │   │   ├── layout/         # Breakpoints
│   │   │   └── errors/         # Failure types
│   │   ├── features/
│   │   │   ├── auth/           # Login/register
│   │   │   ├── library/        # Gestión biblioteca
│   │   │   ├── reader/         # Lectura + TTS
│   │   │   └── settings/       # Preferencias
│   │   └── shared/widgets/
│   ├── pubspec.yaml
│   └── README.md
│
├── oracleJdk-26/               # Java runtime
├── .gitignore
├── README.md                   # Este archivo
├── DEVELOPMENT-STATUS.md
└── lect_sync_project_definition.md
```

---

## API Endpoints

### Autenticación

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| POST | `/api/v1/auth/register` | No | Registrar usuario |
| POST | `/api/v1/auth/login` | No | Login, retorna JWT |
| POST | `/api/v1/auth/refresh` | No | Renovar access token |
| POST | `/api/v1/auth/logout` | Sí | Logout |

### Biblioteca

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| GET | `/api/v1/library` | Sí | Listar libros del usuario |
| POST | `/api/v1/library/import` | Sí | Importar libro (multipart) |
| DELETE | `/api/v1/books/:bookId` | Sí | Eliminar libro |

### Lector

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| GET | `/api/v1/books/:bookId/chapters` | Sí | Listar capítulos |
| GET | `/api/v1/books/:bookId/chapters/:chapterId` | Sí | Contenido capítulo |
| POST | `/api/v1/books/:bookId/chapters/:chapterId/audio` | Sí | Generar/obtener audio TTS |
| PUT | `/api/v1/books/:bookId/progress` | Sí | Guardar progreso |

### Salud

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| GET | `/api/v1/health` | No | Health check |

---

## Configuración

### Variables de Entorno (Backend)

```env
PORT=3000
HOST=127.0.0.1
NODE_ENV=development|production

# Base de datos
DATABASE_URL=postgresql://user:pass@host:5432/dbname

# JWT (mínimo 8 caracteres, 32+ en producción)
JWT_SECRET=tu-secret-seguro

# Rate limiting
RATE_LIMIT_MAX=100
RATE_LIMIT_WINDOW=1 minute

# NVIDIA NIM (GLM-5.1)
NVIDIA_API_KEY=nvapi-...
NVIDIA_API_BASE_URL=https://integrate.api.nvidia.com/v1

# ElevenLabs TTS
TTS_PROVIDER=mock|elevenlabs
ELEVENLABS_API_KEY=...
ELEVENLABS_DEFAULT_VOICE_ID=21m00Tcm4TlvDq8ikWAW
```

---

## Scripts

### Backend

```bash
cd backend

npm run dev          # Desarrollo (tsx watch)
npm run build        # Compilar TypeScript
npm run start        # Producción
npm run test         # Tests (52/52 pasando)
npm run typecheck    # Chequeo de tipos

npm run db:up        # Iniciar PostgreSQL (Docker)
npm run db:push      # Push schema a DB
npm run db:seed      # Insertar datos demo
npm run db:down      # Detener Docker
```

### Frontend

```bash
cd lectorsync

flutter pub get       # Instalar dependencias
flutter run           # Ejecutar app
flutter analyze       # Lint (0 issues)
flutter test          # Tests unitarios
```

---

## Estado del Proyecto

- ✅ Backend Fastify/TypeScript operando
- ✅ Frontend Flutter conectado
- ✅ Autenticación JWT real
- ✅ Importación EPUB + PDF + TXT + MD
- ✅ Lector visual operativo
- ✅ TTS con sincronización palabra-a-palabra
- ✅ Auto-scroll durante lectura
- ✅ ElevenLabs TTS integrado
- ✅ Layouts responsivos (desktop/mobile)
- ✅ 52/52 tests pasando

**Pendientes**: Ver `DEVELOPMENT-STATUS.md`

---

## Licencia

Privado - Todos los derechos reservados