# syntax=docker/dockerfile:1.7

# ---- Stage 1: build ----
# Registro completo: Podman no resuelve nombres cortos sin preguntar.
FROM docker.io/library/node:22-alpine AS builder

WORKDIR /app

# Install ALL deps (incluye devDeps para compilar TypeScript)
COPY package.json package-lock.json ./
# Con una conexión lenta, npm cortaba descargas a medias (EIDLETIMEOUT):
# más margen y reintentos.
RUN npm ci --fetch-timeout=600000 --fetch-retries=5 --fetch-retry-maxtimeout=120000

# Copy TS sources and build to dist/
COPY tsconfig.json ./
COPY src ./src
COPY drizzle ./drizzle
COPY drizzle.config.ts ./
COPY openapi ./openapi

RUN npm run build


# ---- Stage 2: runtime ----
FROM docker.io/library/node:22-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

# Solo deps de producción
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --fetch-timeout=600000 --fetch-retries=5 --fetch-retry-maxtimeout=120000 \
    && npm cache clean --force

# Artefactos compilados + recursos en runtime
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/drizzle ./drizzle
COPY --from=builder /app/openapi ./openapi

# Usuario no-root. El directorio del audio se crea aquí con su dueño: al
# montar el volumen `backend_audio` vacío por primera vez, Docker y Podman
# copian el contenido y los permisos de la imagen, y la app puede escribir
# aunque el resto del sistema de archivos sea de solo lectura.
RUN addgroup -S app && adduser -S app -G app \
    && mkdir -p /app/dist/storage/audio \
    && chown -R app:app /app
USER app

EXPOSE 3000

# Healthcheck simple sobre el puerto (no requiere curl)
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]
