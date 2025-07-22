FROM golang:1.24.5-alpine

# Set working directory
WORKDIR /app

# Copy go module files and download deps (run as root)
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the binary (as root)
RUN CGO_ENABLED=0 GOOS=linux go build -o post-service ./main.go

# Create non-root user and set permissions
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

# Switch to non-root user for runtime only
USER nodejs

# Expose the gRPC port
EXPOSE 50052

# Start the server
CMD ["./post-service"]