FROM node:22-slim AS builder
WORKDIR /app
COPY package.json ./

ENV PUPPETEER_CACHE_DIR=/app/.cache

RUN apt-get update && apt-get install -y unzip --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force

# 尝试安装 chrome-headless-shell (仅 amd64 成功，arm64 会失败跳过，使用 || true 防止报错中断)
RUN npx puppeteer browsers install chrome-headless-shell || true

# 提取 amd64 下下载好的 chrome-headless-shell (如果存在的话)
RUN mkdir -p /app/chrome-extracted && \
    SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" 2>/dev/null | head -n 1) && \
    if [ -n "$SHELL_BIN" ]; then \
        cp -r "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ ; \
    fi

# 清理 node_modules 瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
FROM node:22-slim

COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 安装系统运行依赖，同时安装 chromium（给 arm64 架构保底）
RUN apt-get update && apt-get install -y \
    fonts-wqy-microhei \
    dumb-init \
    chromium \
    chromium-sandbox \
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

# 关键魔法：自适应判定！
# 如果 /app/chrome/ 下存在 Puppeteer 提取的二进制，则保留；
# 如果不存在（如 arm64），则将系统安装的 /usr/bin/chromium 软链接为 /app/chrome/chrome-headless-shell
RUN if [ ! -f "/app/chrome/chrome-headless-shell" ]; then \
        mkdir -p /app/chrome && \
        ln -s /usr/bin/chromium /app/chrome/chrome-headless-shell ; \
    fi

COPY app.js .
COPY channels-hook.yaml .

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]