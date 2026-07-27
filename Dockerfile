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

# 尝试通过 Puppeteer 下载 Chrome Headless Shell
RUN npx puppeteer browsers install chrome-headless-shell || true

# 强化版的 Chrome 查找逻辑：寻找可执行文件 chrome-headless-shell 并复制其所在目录
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
# 提取块：专门用于提取静态 ffmpeg (防止 BuildKit 在 riscv64 找不到镜像报错)
# -------------------------------------------------------------
FROM mwader/static-ffmpeg:6.1 AS ffmpeg-provider


# -------------------------------------------------------------
# 运行阶段
# -------------------------------------------------------------
FROM node:22-slim

ARG TARGETARCH

# 安装依赖、系统 Chromium 以及 FFmpeg（如果是 riscv64 就用 apt 安装，其它用 static-ffmpeg）
RUN apt-get update && apt-get install -y \
    fonts-wqy-microhei \
    dumb-init \
    chromium \
    chromium-sandbox \
    libxfixes3 libx11-6 libx11-xcb1 libxcb1 libxrender1 libxi6 \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxext6 libxrandr2 libgbm1 libasound2 \
    $( [ "$TARGETARCH" = "riscv64" ] && echo "ffmpeg" ) \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# 非 riscv64 架构（即 amd64 / arm64）：从 static-ffmpeg 阶段复制
COPY --link --from=ffmpeg-provider /ffmpeg /usr/local/bin/ffmpeg_static
RUN if [ "$TARGETARCH" != "riscv64" ]; then \
        mv /usr/local/bin/ffmpeg_static /usr/local/bin/ffmpeg ; \
    else \
        rm -f /usr/local/bin/ffmpeg_static ; \
    fi

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