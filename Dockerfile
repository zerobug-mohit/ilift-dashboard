# ─────────────────────────────────────────────────────────────────────────────
# iLIFT Dashboard — single container serving the UI and the API on one origin.
#
# Same-origin is the point: it removes CORS, the browser's local-network
# permission, and any API URL for a user to get wrong. One URL, one service.
# ─────────────────────────────────────────────────────────────────────────────

# ── Stage 1: build the frontend ──────────────────────────────────────────────
FROM node:20-slim AS frontend

WORKDIR /build
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./
# No VITE_API_BASE: the app is served by the same server as the API, so it
# talks to /api on its own origin.
RUN npm run build


# ── Stage 2: R runtime ───────────────────────────────────────────────────────
# rocker/r-ver pins the R version and points at Posit Package Manager, so the
# R packages install as prebuilt binaries rather than compiling from source.
FROM rocker/r-ver:4.4.2

# libxml2 for readxl's dependencies; libsodium for plumber's optional cookie
# support; curl/ssl for anything reaching out. Cleaned up in the same layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libsodium-dev \
        zlib1g-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN install2.r --error --skipinstalled --ncpus -1 \
        plumber \
        dplyr \
        readxl \
        jsonlite \
        digest \
        webutils \
    && rm -rf /tmp/downloaded_packages

WORKDIR /app

COPY backend/ ./backend/
COPY --from=frontend /build/dist ./frontend/dist

# Data lives on a mounted volume so uploads survive a restart or redeploy.
# Without this the container's filesystem is ephemeral on most platforms and
# the dashboard would empty itself every time the service restarts.
ENV ILIFT_DATA_DIR=/data
RUN mkdir -p /data/incoming/nikshay /data/cache
VOLUME ["/data"]

# Reachable from outside the container. The origin allowlist and the
# viewer/admin credentials are what actually restrict access — see auth.R.
ENV ILIFT_HOST=0.0.0.0
ENV ILIFT_PORT=8000
ENV ILIFT_STATIC_DIR=/app/frontend/dist

EXPOSE 8000

# /api/health is deliberately unauthenticated so this works without a secret.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${ILIFT_PORT}/api/health" || exit 1

CMD ["Rscript", "backend/scripts/serve.R"]
