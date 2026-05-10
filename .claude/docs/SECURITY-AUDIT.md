# LectorSync - Auditoría de Seguridad

**Fecha**: 2026-05-09
**Auditor**: Claude (análisis automático)
**Versión del Proyecto**: 0.1.0

---

## Resumen Ejecutivo

El proyecto LectorSync implementa varias prácticas de seguridad sólidas como hashing de contraseñas con scrypt, tokens JWT con tiempo de expiración, y rate limiting. Sin embargo, se identificaron **3 vulnerabilidades de prioridad ALTA** que deben ser abordadas antes del despliegue en producción.

---

## Hallazgos de Seguridad

### 🔴 ALTA - CORS Demasiado Permisivo

**Ubicación**: `backend/src/app.ts:20-23`

```typescript
await app.register(cors, {
  origin: true,  // ❌ Permite cualquier origen
  credentials: true
});
```

**Riesgo**: Un origen malicioso podría realizar solicitudes cross-site con credenciales del usuario.

**Recomendación**:
```typescript
// Producción: especificar orígenes exactos
origin: process.env.NODE_ENV === 'production'
  ? ['https://lectorsync.example.com']
  : true
```

---

### 🟠 ALTA - Refresh Tokens No Revocados en Logout

**Ubicación**: `backend/src/api/v1/routes.ts:233`

```typescript
// TODO: Revocar refresh tokens en base de datos.
```

**Riesgo**: Si un refresh token es robado, el atacante puede obtener acceso indefinidamente aunque el usuario haga logout.

**Recomendación**:
1. Crear tabla `refresh_token_revocations`
2. Al logout, agregar token a lista de revocados
3. Verificar revocación en cada refresh

---

### 🟠 ALTA - JWT_SECRET con Valor por Defecto Débil

**Ubicación**: `backend/src/core/env.ts:8`

```typescript
JWT_SECRET: z.string().min(8).default('lectorsync-dev-secret'),
```

**Riesgo**: En desarrollo, si no se configura JWT_SECRET, usa un valor conocido que podría ser usado en ataques.

**Recomendación**:
```typescript
// En producción, rechazar el valor por defecto
JWT_SECRET: z.string().min(32).refine(
  (val) => val !== 'lectorsync-dev-secret' || process.env.NODE_ENV === 'development',
  { message: 'JWT_SECRET must be changed in production' }
)
```

---

### 🟡 MEDIA - Sin Validación MIME Estricta en Uploads

**Ubicación**: `backend/src/api/v1/routes.ts` (import endpoint)

**Riesgo**: Un usuario podría subir archivos maliciosos disfrazados con extensión .epub.

**Recomendación**:
```typescript
const ALLOWED_MIMES = {
  'application/epub+zip': '.epub',
  'application/pdf': '.pdf',
  'text/plain': ['.txt', '.md']
};
// Verificar magic bytes del archivo, no solo extensión
```

---

### 🟡 MEDIA - Sin Rate Limiting por IP en Rutas de Auth

**Riesgo**: Ataques de fuerza bruta en `/auth/login` podrían pasar desapercibidos.

**Recomendación**:
```typescript
// Agregar rate limit específico para auth
await app.register(authRateLimit, {
  max: 5,
  timeWindow: '15 minute',
  keyGenerator: (req) => req.ip
});
```

---

### 🟡 MEDIA - Falta de Headers de Seguridad

**Riesgo**: Missing headers como CSP, HSTS, X-Frame-Options exponen a clickjacking y XSS.

**Recomendación**:
```typescript
import helmet from '@fastify/helmet';
await app.register(helmet, {
  contentSecurityPolicy: true,
  hsts: { maxAge: 31536000, includeSubDomains: true }
});
```

---

### 🟢 BAJA - No Hay Logs de Intentos de Login Fallidos

**Riesgo**: No hay auditoría para detectar ataques de credential stuffing.

**Recomendación**: Implementar logging estructurado de autenticación.

---

### 🟢 BAJA - Almacenamiento Local de Archivos

**Ubicación**: `backend/src/app.ts:36-40`

```typescript
await app.register(staticPlugin, {
  root: AUDIO_DIR,
  prefix: '/audio/'
});
```

**Riesgo**: Los archivos de audio almacenados localmente no son adecuados para producción horizontalmente escalable.

**Recomendación**: Usar S3 o similar para producción.

---

## Lo Que Está Bien ✅

| Característica | Implementación |
|----------------|----------------|
| Password Hashing | scrypt con salt aleatorio (memory-hard) |
| Tokens JWT | Access token 15min, Refresh 30d |
| Rate Limiting | 100 req/min configurado |
| Validación Input | Zod schemas exhaustivos |
| Ownership Check | Verificación de usuario en libros |
| Secure Storage | flutter_secure_storage en móvil |
| .env en .gitignore | Secrets no se suben al repo |

---

## Checklist de Despliegue Seguro

- [ ] Cambiar `JWT_SECRET` por valor único de 32+ caracteres
- [ ] Configurar CORS con orígenes específicos
- [ ] Usar PostgreSQL con SSL
- [ ] Implementar revocación de refresh tokens
- [ ] Agregar `@fastify/helmet` para headers de seguridad
- [ ] Configurar rate limiting más estricto en auth
- [ ] Implementar logging de autenticación
- [ ] Usar HTTPS en producción
- [ ] Considerar almacenamiento cloud (S3) para archivos

---

## Dependencias con Vulnerabilidades Conocidas

Verificar periódicamente con:
```bash
npm audit                  # Backend
flutter pub outdated       # Frontend
```

---

*Este documento debe actualizarse después de cada sprint de seguridad.*