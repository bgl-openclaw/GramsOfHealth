FROM node:20-slim

ENV PUPPETEER_CACHE_DIR=/app/.cache/puppeteer
WORKDIR /app

# Chromium runtime libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 \
      libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 \
      libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 \
      libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 wget \
    && rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install
COPY server.js ./

ENV PORT=8080
EXPOSE 8080
CMD ["npm", "start"]
