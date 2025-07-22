FROM rust:1.88-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Leverage Docker cache
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release

# Copy actual source
COPY build.rs ./
COPY proto/ proto/
COPY src/ src/

# Build final binary
RUN cargo build --release && strip target/release/server

# Final runtime stage
FROM debian:12.11-slim as final

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    netcat \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r appuser && useradd -r -g appuser appuser

RUN mkdir -p /app/data && chown -R appuser:appuser /app
COPY --from=builder /app/target/release/server /app/server
RUN chown appuser:appuser /app/server

USER appuser
WORKDIR /app

EXPOSE 50053

HEALTHCHECK CMD nc -z localhost 50053 || exit 1

ENTRYPOINT ["/app/server"]