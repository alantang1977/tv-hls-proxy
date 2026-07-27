FROM node:22-slim AS builder
WORKDIR /app
COPY package.json ./

ENV PUPPETEER_CACHE_DIR=/app/.cache

# 依据平台安装解压工具
RUN apt-get update && apt-get install -y unzip --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force

# 尝试通过 Puppeteer 下载 Chrome Headless Shell (适用于 amd64 / 部分 arm64)
# 如果下载失败（比如 riscv64 无官方二进制包），则忽略错误并降级到系统 Chromium
RUN npx puppeteer browsers install chrome-headless-shell || true

# 强化版的 Chrome 查找逻辑：递归寻找可执行文件 chrome-headless-shell 并复制其所在目录
RUN mkdir -p /app/chrome-extracted && \
    SHELL_BIN=$(find /app/.cache -type f -name "chrome-headless-shell" 2>/dev/null | head -n 1) && \
    if [ -n "$SHELL_BIN" ]; then \
        cp -R "$(dirname "$SHELL_BIN")"/.* /app/chrome-extracted/ 2>/dev/null || cp -R "$(dirname "$SHELL_BIN")"/* /app/chrome-extracted/ ; \
    fi

# 清理 node_modules 瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
FROM node:22-slim

# 跨平台静态 ffmpeg (注意：mwader/static-ffmpeg 支持 amd64/arm64，riscv64 需降级从 apt 安装)
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "riscv64" ]; then \
        apt-get update && apt-get install -y ffmpeg --no-install-recommends && rm -rf /var/lib/apt/lists/* ; \
    fi
COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 安装依赖 & 系统 Chromium（作为 riscv64 及缺少包时的保底方案）
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

ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/chrome-extracted/ /app/chrome/

# 自动判断 Chrome 路径：优先用 Puppeteer 提取的，如果没有则使用系统 chromium
RUN if [ -f "/app/chrome/chrome-headless-shell" ]; then \
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