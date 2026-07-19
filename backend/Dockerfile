# syntax=docker/dockerfile:1.7

# ---- Stage 1: build ----
FROM node:22-alpine AS builder

WORKDIR /app

# Install ALL deps (incluye devDeps para compilar TypeScript)
COPY package.json package-lock.json ./
RUN npm ci

# Copy TS sources and build to dist/
COPY tsconfig.json ./
COPY src ./src
COPY drizzle ./drizzle
COPY drizzle.config.ts ./
COPY openapi ./openapi

RUN npm run build


# ---- Stage 2: runtime ----
FROM node:22-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

# Solo deps de producción
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Artefactos compilados + recursos en runtime
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/drizzle ./drizzle
COPY --from=builder /app/openapi ./openapi

# Usuario no-root
RUN addgroup -S app && adduser -S app -G app && chown -R app:app /app
USER app

EXPOSE 3000

# Healthcheck simple sobre el puerto (no requiere curl)
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]
