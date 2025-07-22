# -------- Build Stage --------
FROM golang:1.24.5-alpine AS builder

# Enable Go modules and set working dir
WORKDIR /app

# Copy go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary (CGO disabled for static build)
RUN CGO_ENABLED=0 GOOS=linux go build -o post-service ./main.go

# -------- Runtime Stage --------
FROM alpine:edge

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

# Set working directory and permissions
WORKDIR /app
COPY --from=builder /app/post-service ./
RUN chown -R appuser:appgroup /app

USER appuser

# Expose gRPC port
EXPOSE 50052

# Start the server
CMD ["./post-service"]