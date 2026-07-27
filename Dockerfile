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

# 仅 amd64 下载并提取 chrome-headless-shell
RUN mkdir -p /app/chrome-extracted && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        npx puppeteer browsers install chrome-headless-shell && \
        SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" | head -n 1) && \
        cp -r "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ ; \
    fi

# node_modules 深度清理
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
# Stage 2: Runtime
# -------------------------------------------------------------
FROM node:22-slim
ARG TARGETARCH

COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 安装必要依赖；如果是 arm64，安装 chromium 并在安装后立即清理多余语言包/资源
RUN apt-get update && apt-get install -y \
    fonts-wqy-microhei \
    dumb-init \
    $( [ "$TARGETARCH" = "arm64" ] && echo "chromium chromium-sandbox" ) \
    libxfixes3 libx11-6 libx11-xcb1 libxcb1 libxrender1 libxi6 \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxext6 libxrandr2 libgbm1 libasound2 \
    --no-install-recommends && \
    # 瘦身：移除 Chromium 多余的语言包 (locales) 和无关文件（仅对 arm64 有效）
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

# 统一路径设置
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        echo "PUPPETEER_EXECUTABLE_PATH=/app/chrome/chrome-headless-shell" >> /etc/environment ; \
        ln -s /app/chrome/chrome-headless-shell /usr/local/bin/headless-chrome ; \
    else \
        echo "PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium" >> /etc/environment ; \
        ln -s /usr/bin/chromium /usr/local/bin/headless-chrome ; \
    fi

ENV PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/headless-chrome

COPY app.js .
COPY channels-hook.yaml .

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]