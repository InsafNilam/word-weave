# -------- Build Stage --------
FROM rust:1.88-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    clang \
    clang-dev \
    clang-static \
    llvm-dev \
    llvm-static \
    lld \
    musl-dev \
    openssl-dev \
    openssl-libs-static \
    protobuf-dev \
    protoc \
    git \
    pkgconfig \
    build-base

# Set environment variables for static linking
ENV LIBCLANG_PATH=/usr/lib/llvm20/lib
ENV BINDGEN_EXTRA_CLANG_ARGS="-I/usr/include"
ENV RUSTFLAGS="-C target-feature=-crt-static"

# Set working directory
WORKDIR /app

# Leverage Docker cache for dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release
RUN rm -rf src

# Copy source and build
COPY build.rs ./
COPY src/ src/
RUN cargo build --release && strip target/release/server

# -------- Runtime Stage --------
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# App setup
WORKDIR /app
COPY --from=builder /app/target/release/server ./server
RUN chown -R appuser:appuser /app

USER appuser

# gRPC port
EXPOSE 50053

# Healthcheck (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s CMD nc -z localhost 50053 || exit 1

ENTRYPOINT ["./server"]