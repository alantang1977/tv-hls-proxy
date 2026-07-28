# === 第一阶段：专门安装依赖与深度剪枝 ===
FROM node:22-slim AS builder
WORKDIR /app

COPY package*.json ./

# 核心修复：1. 使用新版的 PUPPETEER_SKIP_DOWNLOAD
#          2. 双重保险，同时保留旧版变量名，并且直接写在 npm install 运行命令的前面
RUN npm config set registry https://registry.npmmirror.com && \
    PUPPETEER_SKIP_DOWNLOAD=true PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true npm install --omit=dev && \
    npm cache clean --force

# node_modules 深度瘦身
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# === 第二阶段：纯净运行环境 ===
FROM node:22-slim

# 1. 复制静态 FFmpeg
COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 2. 安装底层依赖与字体（添加 binutils 用于 strip）
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-wqy-microhei \
    dumb-init \
    binutils \
    libxfixes3 libx11-6 libx11-xcb1 libxcb1 libxrender1 libxi6 \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxext6 libxrandr2 libgbm1 libasound2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

ENV NODE_ENV=production \
    PUPPETEER_EXECUTABLE_PATH=/app/chrome/headless-shell

# 3. 从 builder 阶段只把清理干净的 node_modules 拿过来
COPY --from=builder /app/node_modules ./node_modules

# 4. 根据构建平台拷贝对应的 chromium
ARG TARGETARCH
COPY chromium_${TARGETARCH}/ /app/chrome/

# 5. strip 瘦身 headless-shell 和共享库
RUN strip /app/chrome/headless-shell && \
    strip /app/chrome/*.so 2>/dev/null || true && \
    chmod +x /app/chrome/headless-shell

# 6. 复制业务代码
COPY package.json app.js channels-hook.yaml ./

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]