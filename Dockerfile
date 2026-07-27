FROM node:22-slim AS builder
WORKDIR /app
COPY package.json ./

ENV PUPPETEER_CACHE_DIR=/app/.cache

RUN apt-get update && apt-get install -y unzip --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force && \
    npx puppeteer browsers install chrome-headless-shell

# 递归定位并提取 chrome-headless-shell 所在目录（兼容 amd64 / arm64 目录命名差异）
RUN mkdir -p /app/chrome-extracted && \
    SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" | head -n 1) && \
    test -n "$SHELL_BIN" && \
    cp -R "$(dirname "$SHELL_BIN")"/.* /app/chrome-extracted/ 2>/dev/null || cp -R "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/

# 清理 node_modules 瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
FROM node:22-slim

# mwader/static-ffmpeg 原生支持 amd64 和 arm64，可以直接提取
COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

RUN apt-get update && apt-get install -y \
    fonts-wqy-microhei \
    dumb-init \
    libxfixes3 libx11-6 libx11-xcb1 libxcb1 libxrender1 libxi6 \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxext6 libxrandr2 libgbm1 libasound2 \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
COPY package.json ./

ENV NODE_ENV=production \
    PUPPETEER_EXECUTABLE_PATH=/app/chrome/chrome-headless-shell

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/chrome-extracted/ /app/chrome/

COPY app.js .
COPY channels-hook.yaml .

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]