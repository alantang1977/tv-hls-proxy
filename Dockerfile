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
    npx puppeteer browsers install chrome-headless-shell || npx puppeteer browsers install chrome

# -------------------------------------------------------------
# 强化版提取逻辑：兼容 amd64 与 arm64 的差异
# -------------------------------------------------------------
RUN mkdir -p /app/chrome-extracted && \
    # 1. 优先寻找名称为 chrome-headless-shell 的文件，找不到则寻找名称为 chrome 的文件
    SHELL_BIN=$(find /app/.cache -type f \( -name "chrome-headless-shell" -o -name "chrome" \) | head -n 1) && \
    echo "Found chrome binary at: $SHELL_BIN" && \
    test -n "$SHELL_BIN" && \
    # 2. 将其所在目录下的所有内容平铺拷贝到 /app/chrome-extracted/
    cp -r "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ && \
    # 3. 关键补丁：如果解压出来的主程序叫 chrome 而不叫 chrome-headless-shell，自动建立软链接
    if [ ! -f "/app/chrome-extracted/chrome-headless-shell" ] && [ -f "/app/chrome-extracted/chrome" ]; then \
        ln -s /app/chrome-extracted/chrome /app/chrome-extracted/chrome-headless-shell ; \
    fi

# 清理 node_modules 瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
FROM node:22-slim

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