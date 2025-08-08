# ---------- Build Stage ----------
FROM node:22.17.1-alpine AS builder

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci

# Copy source code and build
COPY . .
RUN npm run build

# ---------- Production Stage ----------
FROM nginx:alpine AS production

COPY ./nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/dist /var/www/html/

COPY env.sh /docker-entrypoint.d/env.sh
RUN dos2unix /docker-entrypoint.d/env.sh
RUN chmod +x /docker-entrypoint.d/env.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["nginx","-g","daemon off;"]
