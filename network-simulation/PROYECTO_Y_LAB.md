# Resumen del Proyecto Completo y Aplicacion del Laboratorio

---

## Tabla de Contenido

1. [Que es LectorSync](#1-que-es-lectorsync)
2. [Que hace la aplicacion](#2-que-hace-la-aplicacion)
3. [Arquitectura del sistema](#3-arquitectura-del-sistema)
4. [Stack tecnologico](#4-stack-tecnologico)
5. [Estado actual del desarrollo](#5-estado-actual-del-desarrollo)
6. [El laboratorio de simulacion de red](#6-el-laboratorio-de-simulacion-de-red)
7. [Como el lab aplica a LectorSync](#7-como-el-lab-aplica-a-lectorsync)
8. [Diagrama de conexion conceptual](#8-diagrama-de-conexion-conceptual)
9. [Tabla de equivalencias final](#9-tabla-de-equivalencias-final)

---

## 1. Que es LectorSync

LectorSync es una aplicacion multiplataforma de lectura sincronizada con audio de alta calidad. Su propuesta central es que mientras el usuario lee un libro digital, una voz narra el texto y **cada palabra se resalta en el momento exacto** en que la voz la pronuncia, con menos de 100 milisegundos de desfase entre el audio y el resaltado visual.

La aplicacion soporta 5 plataformas desde un solo codigo fuente: iOS, Android, macOS, Windows y Linux.

**Usuarios objetivo:**

- Lector ocasional que quiere leer y escuchar al mismo tiempo
- Estudiante de idiomas que mejora comprension auditiva leyendo en otro idioma
- Persona con dislexia que se apoya en el audio para seguir el flujo del texto
- Audiofilo del libro que valora la calidad de la voz narrada

---

## 2. Que hace la aplicacion

### Funcionalidades implementadas

| Funcionalidad | Descripcion | Estado |
|---|---|---|
| Importacion multi-formato | Soporta EPUB, PDF, TXT y Markdown | Funcionando |
| Autenticacion JWT | Registro, login, refresh token, logout | Funcionando |
| Lector visual | Navegacion por capitulos, progreso persistente | Funcionando |
| Text-to-Speech | TTS del dispositivo + ElevenLabs con timestamps | Funcionando |
| Sincronizacion palabra-a-palabra | Resaltado visual sincronizado con el audio | Funcionando |
| Auto-scroll | Desplazamiento automatico al parrafo activo durante TTS | Funcionando |
| ElevenLabs | Proveedor de voz premium con timestamps por caracter | Integrado |
| Layouts responsivos | Tres layouts: compacto, medio y expandido (desktop) | Funcionando |
| Tests automatizados | 52/52 tests del backend pasando, 0 issues en frontend | Verificado |

### Flujo principal del usuario

```
1. El usuario abre la aplicacion
2. Se registra o inicia sesion
3. Importa un libro (EPUB, PDF, TXT o Markdown)
4. Abre el libro y navega a un capitulo
5. Presiona "Reproducir"
6. La voz comienza a narrar el texto
7. Cada palabra se resalta en el momento exacto que se pronuncia
8. La pantalla se desplaza automaticamente siguiendo la lectura
9. El progreso se guarda automaticamente
10. El usuario puede pausar, cambiar velocidad o cambiar de capitulo
```

---

## 3. Arquitectura del sistema

LectorSync sigue el **modelo cliente-servidor**. La aplicacion Flutter es el cliente y el backend Node.js es el servidor. Toda la comunicacion pasa por peticiones HTTP/REST.

```
+----------------------------+              +----------------------------+
|   CLIENTE (Flutter App)    |    HTTP      |   SERVIDOR (Node.js)       |
|                            |    REST      |                            |
|  Presentacion:             |    JSON      |  API Gateway:              |
|  - Widgets de UI           | <==========> |  - Fastify (framework)     |
|  - Layouts responsivos     |    JWT       |  - Rutas /api/v1/*         |
|  - Temas de lectura        |              |  - Middleware de auth      |
|                            |              |                            |
|  Logica de negocio:        |              |  Servicios:                |
|  - BLoC (gestion estado)   |              |  - Auth (JWT tokens)       |
|  - Sincronizacion audio    |              |  - Library (CRUD libros)   |
|  - Busqueda binaria O(logn)|              |  - Reader (capitulos)      |
|                            |              |  - TTS (ElevenLabs)        |
|  Datos locales:            |              |                            |
|  - SecureStorage (tokens)  |              |  Base de datos:            |
|  - Cache de audio          |              |  - PostgreSQL (Drizzle ORM)|
|  - Progreso local          |              |  - Parsers (EPUB/PDF/TXT)  |
+----------------------------+              +----------------------------+
```

### Flujo de una peticion tipica

```
Flutter App                          Backend Fastify
    |                                      |
    |--- POST /api/v1/auth/login --------->|
    |    {email, password}                 |
    |                                      |-- Busca usuario en PostgreSQL
    |                                      |-- Compara hash scrypt
    |                                      |-- Genera JWT tokens
    |<-- 200 {access_token, refresh} ------|
    |                                      |
    |--- GET /api/v1/library ------------->|
    |    Header: Authorization: Bearer JWT |
    |                                      |-- Valida JWT
    |                                      |-- Consulta libros del usuario
    |<-- 200 [{id, title, author, ...}] ---|
    |                                      |
    |--- POST /chapters/:id/audio -------->|
    |    {voice_id, provider}              |
    |                                      |-- Llama API de ElevenLabs
    |                                      |-- Recibe audio + timestamps
    |<-- 200 {audio_url, timestamps} ------|
    |                                      |
    |   (Flutter reproduce audio y         |
    |    resalta palabras en tiempo real)   |
```

---

## 4. Stack tecnologico

### Backend

| Componente | Tecnologia | Para que se usa |
|---|---|---|
| Runtime | Node.js 22+ | Entorno de ejecucion JavaScript en servidor |
| Lenguaje | TypeScript 5.7 | Tipado estatico para robustez |
| Framework | Fastify 5.0 | Framework HTTP rapido con validacion built-in |
| Base de datos | PostgreSQL 16 | Almacena usuarios, libros, progreso, audio |
| ORM | Drizzle ORM | Acceso type-safe a la base de datos |
| Autenticacion | @fastify/jwt | Tokens JWT para sesiones |
| Validacion | Zod | Validacion de inputs en todos los endpoints |
| Parsers | pdfjs-dist, adm-zip, xml2js | Extraccion de texto de EPUB, PDF, TXT, MD |
| TTS | ElevenLabs API | Sintesis de voz con timestamps por caracter |
| Hash | Node.js crypto (scrypt) | Hash seguro de contrasenas |

### Frontend (Flutter)

| Componente | Tecnologia | Para que se usa |
|---|---|---|
| Framework | Flutter 3.24+ | UI multiplataforma nativa |
| Estado | flutter_bloc (BLoC) | Gestion de estado predecible y testeable |
| Navegacion | go_router | Enrutamiento declarativo |
| Inyeccion | get_it | Inyeccion de dependencias |
| HTTP | Dio | Cliente HTTP con interceptors JWT |
| Storage | flutter_secure_storage | Almacenamiento cifrado de tokens |
| Audio | just_audio | Reproductor de audio de alta calidad |
| TTS | flutter_tts | Text-to-Speech del dispositivo (offline) |

### Arquitectura de software

| Principio | Como se aplica |
|---|---|
| Clean Architecture | 3 capas: Presentation, Domain, Data |
| SOLID | Cada clase tiene una responsabilidad; interfaces segregadas |
| BLoC Pattern | Separacion estricta entre UI y logica de negocio |
| Repository Pattern | Abstraccion sobre fuentes de datos (API, local) |

---

## 5. Estado actual del desarrollo

### Componentes completados

```
Backend (Node.js + TypeScript + Fastify):
  [x] Servidor Fastify configurado con CORS y rate limiting
  [x] Autenticacion completa (register, login, refresh, logout)
  [x] Contrasenas hasheadas con scrypt + salt aleatorio
  [x] Biblioteca: listar, importar, eliminar libros
  [x] Reader: capitulos, contenido, progreso
  [x] Parsers: EPUB, PDF, TXT, Markdown (4 formatos)
  [x] TTS: ElevenLabs con timestamps por caracter
  [x] Validacion Zod en todos los endpoints
  [x] 52/52 tests pasando

Frontend (Flutter):
  [x] App multiplataforma (iOS, Android, macOS, Windows, Linux)
  [x] Login y registro con JWT
  [x] Biblioteca con importacion de 4 formatos
  [x] Lector visual con navegacion por capitulos
  [x] TTS con sincronizacion palabra-a-palabra
  [x] Auto-scroll al parrafo activo
  [x] Layouts responsivos (3 breakpoints)
  [x] Microinteracciones desktop (hover, animaciones)
  [x] Accesibilidad (Semantics, screen reader support)
  [x] 0 issues en flutter analyze
```

### Endpoints de la API

| Metodo | Endpoint | Descripcion |
|---|---|---|
| POST | `/api/v1/auth/register` | Registrar usuario nuevo |
| POST | `/api/v1/auth/login` | Iniciar sesion, retorna JWT |
| POST | `/api/v1/auth/refresh` | Renovar access token |
| POST | `/api/v1/auth/logout` | Cerrar sesion |
| GET | `/api/v1/library` | Listar libros del usuario |
| POST | `/api/v1/library/import` | Importar libro (multipart) |
| DELETE | `/api/v1/books/:bookId` | Eliminar libro |
| GET | `/api/v1/books/:bookId/chapters` | Listar capitulos |
| GET | `/api/v1/books/:bookId/chapters/:chapterId` | Contenido de un capitulo |
| POST | `/api/v1/books/:bookId/chapters/:chapterId/audio` | Generar audio TTS |
| PUT | `/api/v1/books/:bookId/progress` | Guardar progreso de lectura |
| GET | `/api/v1/health` | Health check |

### Como ejecutar el proyecto

```bash
# Terminal 1 — Backend
cd backend
npm install
npm run db:up        # Inicia PostgreSQL con Docker
npm run db:push      # Crea las tablas
npm run db:seed      # Inserta datos de prueba
npm run dev          # Servidor en http://localhost:3000

# Terminal 2 — Frontend
cd lectorsync
flutter pub get
flutter run -d chrome   # O cualquier plataforma
```

---

## 6. El laboratorio de simulacion de red

### Que es

Una simulacion funcional del modelo cliente-servidor usando **sockets TCP reales** sobre localhost. Demuestra los tres pilares de la comunicacion en red:

1. **Inicio de sesion**: Un cliente se autentica con usuario y contrasena
2. **Envio de mensajes**: Un cliente envia un mensaje a otro a traves del servidor
3. **Confirmacion de recepcion (ACK)**: El servidor confirma la entrega del mensaje

### Estructura

```
network-simulation/
├── package.json           # Dependencias independientes (tsx, typescript)
├── tsconfig.json          # Configuracion TypeScript
├── src/
│   ├── protocol.ts        # Tipos compartidos, serializacion NDJSON
│   ├── server.ts          # Servidor TCP: auth, enrutamiento, ACK, broadcast
│   └── client.ts          # Cliente CLI interactivo: login, envio, recepcion
├── DOCUMENTACION.md       # Documentacion tecnica del protocolo
└── GUIA_LABORATORIO.md    # Guia paso a paso de ejecucion
```

### Como funciona

```
Terminal 1:  npm run server     →  Servidor escucha en puerto 3500
Terminal 2:  npm run client     →  Alice se conecta y hace login
Terminal 3:  npm run client     →  Bob se conecta y hace login

Alice escribe:  /msg bob Hola Bob!
  → El servidor recibe el mensaje
  → Lo reenvia a Bob
  → Envia ACK a Alice: "Mensaje [a1b2c3d4] entregado a bob"
Bob ve:  [DE alice] Hola Bob!
```

### Tecnologias del lab

| Tecnologia | Uso |
|---|---|
| Node.js | Entorno de ejecucion |
| TypeScript | Tipado estatico |
| Modulo `net` | Sockets TCP nativos (sin dependencias externas) |
| Modulo `readline` | Interfaz CLI interactiva |
| NDJSON | Formato de mensajes sobre TCP (JSON + salto de linea) |
| TCP | Protocolo de transporte confiable |

---

## 7. Como el lab aplica a LectorSync

El laboratorio demuestra **exactamente el mismo modelo** que usa LectorSync, pero en una capa mas baja y visible. LectorSync usa HTTP/REST que abstrae la complejidad; el lab muestra esa complejidad directamente.

### 7.1 Inicio de sesion — Mismo patron, diferente capa

**En el lab (TCP crudo):**
```
Cliente envía:    {"type":"LOGIN","from":"alice","content":"alice123"}
Servidor valida:  Compara contra USERS_DB["alice"] === "alice123"
Servidor responde: {"type":"LOGIN_OK","content":"Bienvenido, alice"}
```

**En LectorSync (HTTP/REST):**
```
Cliente envia:    POST /api/v1/auth/login  {"email":"user@mail.com","password":"..."}
Servidor valida:  Hash scrypt contra PostgreSQL
Servidor responde: 200 {"access_token":"eyJ...","refresh_token":"..."}
```

**Comparacion directa:**

| Aspecto | Lab (sockets TCP) | LectorSync (HTTP/REST) |
|---|---|---|
| El cliente envia credenciales | `{type:"LOGIN", from:"alice", content:"alice123"}` | `POST /auth/login {email, password}` |
| El servidor valida | Compara contra `USERS_DB` en memoria | Compara hash scrypt contra PostgreSQL |
| Respuesta exitosa | `{type:"LOGIN_OK"}` | `200 {access_token, refresh_token}` |
| Respuesta fallida | `{type:"LOGIN_FAIL"}` | `401 Unauthorized` |
| Que se guarda en el servidor | Socket en `connectedClients` Map | JWT es stateless (no guarda sesion) |
| Que se guarda en el cliente | Variable `isLoggedIn = true` | Token en SecureStorage cifrado |

**Conclusion**: El flujo de autenticacion del lab es la version "desnuda" de lo que hace LectorSync. En el lab se ve el JSON viajar literalmente por TCP. En LectorSync, HTTP abstrae esa capa, pero el proceso es identico: cliente envia datos, servidor valida, responde OK o FAIL.

---

### 7.2 Envio de mensajes — Mismo concepto de enrutamiento

**En el lab (TCP crudo):**
```
Alice envia:     {"type":"MESSAGE","to":"bob","content":"Hola Bob!"}
Servidor busca:  connectedClients.get("bob") → socket de Bob
Servidor reenvia: Escribe el mensaje en el socket de Bob
```

**En LectorSync (HTTP/REST):**
```
Flutter envia:   POST /api/v1/books/:id/chapters/:id/audio {voice_id, provider}
Servidor procesa: Llama API de ElevenLabs, genera audio
Servidor responde: 200 {audio_url, word_timestamps}
```

**Comparacion directa:**

| Aspecto | Lab | LectorSync |
|---|---|---|
| Cliente envia solicitud | `{type:"MESSAGE", to:"bob", content:"Hola"}` | `POST /chapters/:id/audio` |
| Servidor procesa | Busca socket destino en Map | Genera audio TTS con ElevenLabs |
| Servidor entrega resultado | Escribe en socket de Bob | Responde con `{audio_url, timestamps}` |
| Si falla | `{type:"ERROR", content:"no conectado"}` | HTTP 404 o 500 con body de error |
| Intermediario | El servidor reenvia entre clientes | El backend llama a ElevenLabs por el cliente |

**Conclusion**: En ambos casos el servidor actua como **intermediario central**. En el lab, Alice no puede hablar directamente con Bob; todo pasa por el servidor. En LectorSync, la app Flutter no llama directamente a ElevenLabs; pasa por el backend que gestiona API keys, cache y seguridad.

---

### 7.3 Confirmacion de recepcion (ACK) — Mismo mecanismo de confiabilidad

**En el lab (ACK explicito):**
```
Servidor confirma a Alice:  {"type":"ACK","id":"a1b2c3d4","content":"entregado a bob"}
```

**En LectorSync (ACK implicito via HTTP):**
```
Servidor responde a Flutter:  HTTP 200 {audio_url: "...", word_timestamps: [...]}
                              (el status 200 ES la confirmacion)
```

**Comparacion directa:**

| Aspecto | Lab | LectorSync |
|---|---|---|
| Servidor confirma | `{type:"ACK", id:"a1b2c3d4"}` explicito | HTTP 200/204 (el status code es el ACK) |
| Identificador unico | `id` generado con `crypto.randomBytes` | UUID de cada recurso en PostgreSQL |
| Si no se puede entregar | `{type:"ERROR"}` explicito | HTTP 4xx/5xx con body de error |
| El remitente sabe que llego | Ve el mensaje ACK en su terminal | Recibe la respuesta HTTP exitosa |

**Conclusion**: HTTP tiene ACK implicito porque cada respuesta HTTP confirma que el servidor proceso la peticion. El lab hace este ACK explicito y visible para que se entienda el concepto subyacente.

---

### 7.4 Protocolo de comunicacion — La capa que HTTP abstrae

| Aspecto | Lab (visible) | LectorSync (abstraido por HTTP) |
|---|---|---|
| Transporte | TCP directo (modulo `net`) | TCP + HTTP (Fastify / Dio) |
| Formato de mensaje | NDJSON: JSON + `\n` como delimitador | JSON en body HTTP |
| Delimitacion de mensajes | Salto de linea `\n` manual | Header `Content-Length` de HTTP |
| Buffer de datos parciales | Manejo manual en `parseBuffer()` | HTTP lo maneja automaticamente |
| Tipos de mensaje | Enum `MessageType` (LOGIN, MESSAGE, ACK) | Metodos HTTP (GET, POST, PUT, DELETE) |
| Enrutamiento | `switch(msg.type)` en el servidor | Router de Fastify por URL + metodo |
| Autenticacion | Campo `from` en cada mensaje | Header `Authorization: Bearer JWT` |

**Conclusion**: El lab muestra lo que HTTP hace "detras de escenas". Cuando LectorSync hace `POST /api/v1/auth/login`, por debajo TCP abre una conexion, envia bytes con headers HTTP + JSON, y el servidor parsea esos bytes exactamente como lo hace el lab con `parseBuffer()`.

---

## 8. Diagrama de conexion conceptual

```
                     EL LAB                            LECTORSYNC
               (TCP crudo visible)               (HTTP abstrae TCP)

  TRANSPORTE    socket TCP (net)       ══════     socket TCP (net)
                Nosotros manejamos                HTTP lo maneja por
                el buffer y \n                    nosotros con headers
                                                  y Content-Length

  PROTOCOLO     NDJSON protocol        ══════     HTTP/REST protocol
                {type, from, to,                  GET /api/v1/library
                 content, timestamp}              POST /api/v1/auth/login
                                                  + JSON body + JWT header

  SERVIDOR      server.ts              ══════     Fastify (routes.ts)
                switch(msg.type)                  router.post('/auth/login')
                handleLogin()                     authRoutes()
                handleMessage()                   readerRoutes()
                handleDisconnect()                logoutRoute()

  CLIENTE       client.ts (CLI)        ══════     Flutter App (UI)
                readline + terminal               BLoC + widgets + Dio
                /msg bob Hola                     Boton "Reproducir" → API

  ESTADO        connectedClients Map   ══════     PostgreSQL + JWT
                en memoria RAM                    persistente en disco
```

### Capas de red en ambos sistemas

```
         Lab                                    LectorSync
  ┌─────────────────┐                    ┌─────────────────┐
  │  Aplicacion     │                    │  Aplicacion     │
  │  (client.ts /   │                    │  (Flutter /     │
  │   server.ts)    │                    │   Fastify)      │
  ├─────────────────┤                    ├─────────────────┤
  │  Protocolo      │                    │  Protocolo      │
  │  NDJSON         │  ← El lab vive    │  HTTP/REST      │
  │  (nosotros lo   │     en esta       │  (Fastify lo    │
  │   construimos)  │     capa          │   maneja)       │
  ├─────────────────┤                    ├─────────────────┤
  │  Transporte     │                    │  Transporte     │
  │  TCP            │  ← Ambos usan    │  TCP            │
  │  (modulo net)   │     la misma     │  (modulo net)   │
  │                 │     capa base    │                 │
  ├─────────────────┤                    ├─────────────────┤
  │  Red            │                    │  Red            │
  │  IP (localhost) │  ← 127.0.0.1     │  IP (localhost) │
  └─────────────────┘                    └─────────────────┘
```

---

## 9. Tabla de equivalencias final

### Conceptos de red demostrados

| Concepto de red | Se ve en el Lab | LectorSync lo usa asi |
|---|---|---|
| Conexion TCP | `socket.connect(3500)` | Dio abre conexion HTTP al backend |
| Handshake TCP | Automatico al conectar (SYN, SYN-ACK, ACK) | Automatico en cada peticion HTTP |
| Autenticacion | LOGIN → LOGIN_OK / LOGIN_FAIL | POST /auth/login → JWT / 401 |
| Request-Response | MESSAGE → ACK | POST /chapters/audio → 200 + audio_url |
| Estado del servidor | `connectedClients` Map en memoria | PostgreSQL (persistente) + JWT (stateless) |
| Broadcast | Notificar a todos los sockets conectados | No aplica (REST es 1:1, no broadcast) |
| Desconexion | socket close → cleanup del Map | Token JWT expira → re-login |
| Manejo de errores | `{type:"ERROR"}` explicito | HTTP 4xx/5xx status codes |
| Serializacion | `JSON.stringify(msg) + '\n'` | `JSON.stringify(body)` + headers HTTP |
| Deserializacion | `parseBuffer()` manual | HTTP Content-Length automatico |
| Identificadores | `generateId()` con crypto | UUID de PostgreSQL |
| Enrutamiento | `switch(msg.type)` | Router Fastify por URL + metodo |

### Resumen de la relacion

```
El laboratorio demuestra que LectorSync es un sistema
cliente-servidor real. Los principios fundamentales de
la comunicacion en red estan presentes en ambos:

  Lab (basico)                    LectorSync (produccion)
  ─────────────                   ──────────────────────
  1 servidor TCP      ────────►   1 backend Fastify
  2 clientes CLI      ────────►   N clientes Flutter
  Login por socket    ────────►   Login por HTTP + JWT
  Mensajes JSON       ────────►   API REST + JSON
  ACK explicito       ────────►   HTTP 200 implicito
  Buffer manual       ────────►   HTTP automatico
  Map en memoria      ────────►   PostgreSQL persistente

  Mismos principios, diferente nivel de abstraccion.
```

---

## Conclusiones

1. **El modelo cliente-servidor es universal**: Desde un chat TCP basico hasta una aplicacion multiplataforma de produccion, el patron es el mismo. Un servidor central gestiona la logica y los clientes se conectan a el.

2. **HTTP abstrae la complejidad de TCP**: El lab muestra el trabajo que HTTP hace automaticamente: delimitar mensajes, manejar buffers parciales, confirmar recepciones. LectorSync usa HTTP a traves de Fastify y Dio sin tener que preocuparse por estos detalles.

3. **Los mismos conceptos escalan**: Login, envio de datos, confirmacion de recepcion y manejo de errores funcionan igual en un chat de 2 usuarios que en una aplicacion con miles de usuarios. La diferencia es la capa de abstraccion y la infraestructura de soporte (base de datos, cache, balanceadores).

4. **El lab es la base de LectorSync**: Sin comprender como funcionan los sockets TCP, los buffers y los protocolos de mensajes, seria dificil entender por que LectorSync necesita un backend, como viajan los tokens JWT, o por que la comunicacion Flutter-Fastify es confiable.
