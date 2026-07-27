FROM node:22-slim AS builder
WORKDIR /app
COPY package.json ./

RUN apt-get update && apt-get install -y unzip --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_CACHE_DIR=/app/.cache

RUN npm config set registry https://registry.npmmirror.com && \
    npm install --omit=dev && \
    npm install ws yaml && \
    npm cache clean --force && \
    npx puppeteer browsers install chrome-headless-shell

RUN mkdir -p /app/chrome-extracted && \
    CHROME_PATH=$(find /app/.cache/chrome-headless-shell/ \
        -type d -name "chrome-headless-shell-*" | head -n 1) && \
    test -n "$CHROME_PATH" && \
    cp -R "$CHROME_PATH"/. /app/chrome-extracted/

RUN find /app/node_modules -type d -name "doc" -not -path "*/yaml/*" -exec rm -rf {} + && \
    find /app/node_modules -type d \( -name "docs" -o -name "test" -o -name "tests" -o -name "samples" \) -exec rm -rf {} + && \
    find /app/node_modules -type f \( -name "*.md" -o -name "*.ts" -o -name "*.js.map" \) -delete

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