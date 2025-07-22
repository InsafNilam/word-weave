# ------------ Build Stage ------------
FROM node:22.17.1-alpine AS builder

# Set working directory
WORKDIR /app

# Install only dependencies first for layer caching
COPY package*.json ./
RUN npm ci

# Copy the rest of the app
COPY . .

# ------------ Runtime Stage ------------
FROM node:22.17.1-alpine

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    mkdir -p /app && chown -R nodejs:nodejs /app

# Set working directory and permissions
WORKDIR /app
USER nodejs

# Copy only needed files from builder
COPY --chown=nodejs:nodejs --from=builder /app ./

# Install only production dependencies
RUN npm ci --only=production

EXPOSE 8080

# Healthcheck (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:8080/ || exit 1

CMD ["node", "src/index.js"]
