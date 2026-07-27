# 1. 编译阶段：仅 amd64 寻找并提取 chrome-headless-shell
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

# 仅 amd64 下载并提取 chrome-headless-shell；arm64 直接跳过
RUN mkdir -p /app/chrome-extracted && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        npx puppeteer browsers install chrome-headless-shell && \
        SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" | head -n 1) && \
        cp -r "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ ; \
    fi

# 清理 node_modules 瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
# 2. 运行阶段：按架构精确分支，零冗余
# -------------------------------------------------------------
FROM node:22-slim
ARG TARGETARCH

COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 基础依赖：arm64 装 chromium，amd64 绝不安装 chromium
RUN apt-get update && apt-get install -y \
    fonts-wqy-microhei \
    dumb-init \
    $( [ "$TARGETARCH" = "arm64" ] && echo "chromium chromium-sandbox" ) \
    libxfixes3 libx11-6 libx11-xcb1 libxcb1 libxrender1 libxi6 \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxext6 libxrandr2 libgbm1 libasound2 \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
COPY package.json ./

ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/chrome-extracted/ /app/chrome/

# 统一路径路径配置（不再搞软链接映射，直接指定真实可执行文件）
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