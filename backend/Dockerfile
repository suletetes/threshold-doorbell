# backend/Dockerfile
# ===================
# Multi-stage Node 22 build targeting linux/arm64 (AWS Graviton2 Fargate).
# Produces a minimal runtime image — no dev tools, no source files.
#
# Build (from repo root):
#   docker buildx build --platform linux/arm64 -t threshold-backend:latest ./backend
#
# Run locally for smoke-test (on any arch):
#   docker run --rm -p 8080:8080 --env-file backend/.env threshold-backend:latest
#
# Push to ECR:
#   docker tag threshold-backend:latest \
#     356650046555.dkr.ecr.us-east-1.amazonaws.com/threshold-backend:latest
#   docker push \
#     356650046555.dkr.ecr.us-east-1.amazonaws.com/threshold-backend:latest
#
# Implements Phase 0.1 from PROD_READINESS_TODOS.md:
#   multi-stage, Node 22 slim, npm ci + npm run build, node dist/server.js,
#   EXPOSE 8080, non-root USER node, SIGTERM/SIGINT preserved (server.ts).

# ── Stage 1: build ───────────────────────────────────────────────────────────
FROM node:22-slim AS builder

WORKDIR /build

# Copy manifests first — layer cache hits when only source changes
COPY package.json package-lock.json ./

# Install all deps including devDeps (tsc needs them)
# --ignore-scripts: never run arbitrary postinstall from third-party packages
RUN npm ci --ignore-scripts

# Copy source and config, then compile TypeScript → dist/
COPY tsconfig.json tsconfig.build.json ./
COPY src/ ./src/

RUN npm run build
# Produces /build/dist/

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM node:22-slim AS runtime

# node:slim ships with a non-root 'node' user (uid 1000) — use it
USER node
WORKDIR /app

# Install production deps only (no tsc, no vitest, no eslint)
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

# Copy compiled output from the build stage
COPY --chown=node:node --from=builder /build/dist ./dist

# Copy static assets (visitor page served at GET /)
COPY --chown=node:node src/public ./dist/public

# ── Environment & runtime config ─────────────────────────────────────────────
ENV NODE_ENV=production

# Port must match config.ts default (8080) and the ALB target group
EXPOSE 8080

# Healthcheck calls /ready (implemented in app.ts:186).
# ALB also probes /ready independently; this covers docker run smoke-tests.
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e \
    "fetch('http://localhost:8080/ready')\
      .then(r => process.exit(r.ok ? 0 : 1))\
      .catch(() => process.exit(1))"

# server.ts registers SIGTERM + SIGINT handlers that drain WebSocket connections
# before exiting — ECS sends SIGTERM on task stop, so graceful shutdown works.
CMD ["node", "dist/server.js"]
