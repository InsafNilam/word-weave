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
FROM node:22.17.1-alpine AS production

WORKDIR /app

# Install static server
RUN npm i -g serve

# Copy build output from builder stage
COPY --from=builder /app/dist ./dist

EXPOSE 5173

CMD ["serve", "-s", "dist", "-l", "5173"]
