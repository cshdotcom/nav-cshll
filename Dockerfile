# ============================================================================
# 发现导航 (Nav) - Multi-stage Dockerfile
# Source: https://github.com/liuzi6612/nav
# Fork:   https://github.com/cshdotcom/nav-cshll
# ============================================================================
# Stage 1: Build the Angular static site using Node.js + pnpm
# Stage 2: Serve the static files with nginx
# ============================================================================

# ---------- Stage 1: Builder ----------
FROM node:22-bookworm-slim AS builder

# Native build deps for `sharp` and `puppeteer` postinstall scripts.
# We skip puppeteer's Chrome download because the build does not need
# a real browser unless spiderIcon/spiderTitle/spiderDescription are
# explicitly set to 'EMPTY' or 'ALWAYS' in data/settings.json.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        make \
        g++ \
        libc6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Enable pnpm via corepack (bundled with Node.js >= 16.10)
RUN corepack enable && corepack prepare pnpm@latest --activate

# Skip downloading Chromium for puppeteer - not needed for default build
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
# Better build reproducibility
ENV CI=true
ENV NODE_ENV=production

# Cache: install dependencies first (only package.json + lockfile changed rarely)
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build the static site. This runs:
#   1. `init`   - processes data/db.json + data/settings.json + nav.config.yaml
#   2. `build`  - writes SEO/HTML templates, then `ng build` outputs to dist/browser
RUN pnpm run build

# Verify build output exists
RUN ls -la dist/browser/index.html

# ---------- Stage 2: Runtime ----------
FROM nginx:1.27-alpine AS runtime

LABEL org.opencontainers.image.title="nav"
LABEL org.opencontainers.image.description="发现导航 - lightweight navigation website"
LABEL org.opencontainers.image.source="https://github.com/cshdotcom/nav-cshll"
LABEL org.opencontainers.image.licenses="GPL-3.0"
LABEL maintainer="cshdotcom"

# Clear default nginx static site
RUN rm -rf /usr/share/nginx/html/*

# Copy built static files from builder stage
COPY --from=builder /app/dist/browser /usr/share/nginx/html

# Copy custom nginx config (SPA fallback, gzip, cache headers)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:80/ || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
