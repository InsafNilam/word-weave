# Use official Node.js Alpine image
FROM node:22.17.1-alpine

# Set working directory
WORKDIR /app

# Install dependencies with clean cache handling
COPY package*.json ./
RUN npm ci --only=production

# Copy rest of the source
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

# Use non-root user for safety
USER nodejs

# Only expose gRPC port
EXPOSE 50051

# Start the server
CMD ["node", "src/index.js"]
