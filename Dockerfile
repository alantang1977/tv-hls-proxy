# -------------------------------------------------------------
# Stage 1: Builder
# -------------------------------------------------------------
FROM node:22-slim AS builder
ARG TARGETARCH
WORKDIR /app
COPY package.json ./

ENV PUPPETEER_CACHE_DIR=/app/.cache

RUN apt-get update && apt-get install -y unzip --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force

# Extract chrome-headless-shell on amd64
RUN mkdir -p /app/chrome-extracted && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        npx puppeteer browsers install chrome-headless-shell && \
        SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" | head -n 1) && \
        cp -r "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ ; \
    fi

# Clean up node_modules
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
# Stage 2: Runtime
# -------------------------------------------------------------
FROM node:22-slim
ARG TARGETARCH

COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# Install all missing Chromium runtime dependencies for Debian Bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-wqy-microhei \
    dumb-init \
    ca-certificates \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    $( [ "$TARGETARCH" = "arm64" ] && echo "chromium chromium-sandbox" ) && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        rm -rf /usr/lib/chromium/locales/* && \
        rm -rf /usr/share/icons/* /usr/share/pixmaps/* ; \
    fi && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

WORKDIR /app
COPY package.json ./

ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/chrome-extracted/ /app/chrome/

# Link the correct binary based on target arch
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        ln -sf /app/chrome/chrome-headless-shell /usr/local/bin/headless-chrome ; \
    else \
        ln -sf /usr/bin/chromium /usr/local/bin/headless-chrome ; \
    fi

ENV PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/headless-chrome

COPY app.js .
COPY channels-hook.yaml .

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]