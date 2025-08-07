ARG RUST_VERSION=1.88
ARG APP_NAME=like-service

# -------- Build Stage --------
FROM rust:${RUST_VERSION}-alpine AS builder
ARG APP_NAME 

# Set working directory
WORKDIR /app

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

RUN --mount=type=bind,source=src,target=src \
    --mount=type=bind,source=build.rs,target=build.rs \
    --mount=type=bind,source=Cargo.toml,target=Cargo.toml \
    --mount=type=bind,source=Cargo.lock,target=Cargo.lock \
    --mount=type=cache,target=/app/target/ \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    --mount=type=cache,target=/usr/local/cargo/registry/ \
    cargo build --locked --release && \
    cp ./target/release/server /bin/server

# -------- Runtime Stage --------
FROM alpine:3.22.1 AS runtime

ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

# Install C++ runtime libraries
RUN apk add --no-cache libgcc libstdc++ curl netcat-openbsd

USER appuser

# Copy the executable from the "build" stage.
COPY --from=builder /bin/server /bin/

# gRPC port
EXPOSE 50053

# Healthcheck (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s CMD nc -z localhost 50053 || exit 1

# What the container should run when it is started.
CMD ["/bin/server"]