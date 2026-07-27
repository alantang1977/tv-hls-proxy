# -------------------------------------------------------------
# Stage 1: Builder
# -------------------------------------------------------------
FROM node:22-slim AS builder
ARG TARGETARCH
WORKDIR /app

COPY package.json ./

# 安装 curl 和 tar 方便拉取解压二进制文件
RUN apt-get update && apt-get install -y curl tar --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force

# 根据架构下载对应的预编译 chromium-headless-shell 压缩包并解压到 /app/chrome
RUN mkdir -p /app/chrome && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        URL="https://github.com/Aletherium/chromium-headless-shell/releases/download/chromedp-148.0.7778.97/chromium-headless-shell-linux-amd64.tar.gz" ; \
    else \
        URL="https://github.com/Aletherium/chromium-headless-shell/releases/download/chromedp-148.0.7778.97/chromium-headless-shell-linux-arm64.tar.gz" ; \
    fi && \
    curl -sSL "$URL" | tar -xz -C /app/chrome/

# node_modules 深度清理
RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

# -------------------------------------------------------------
# Stage 2: Runtime
# -------------------------------------------------------------
FROM node:22-slim

COPY --from=mwader/static-ffmpeg:6.1 /ffmpeg /usr/local/bin/ffmpeg

# 安装精简后的运行依赖（基于 ldd 验证，支持中文字体）
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-wqy-microhei \
    dumb-init \
    ca-certificates \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatspi0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libdrm2 \
    libxkbcommon0 \
    libasound2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

WORKDIR /app
COPY package.json ./

ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/chrome/ /app/chrome/

# 精准创建软链接：指向 /app/chrome/headless-shell
RUN ln -sf /app/chrome/headless-shell /usr/local/bin/headless-chrome

ENV PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/headless-chrome

COPY app.js .
COPY channels-hook.yaml .

EXPOSE 3000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "app.js"]