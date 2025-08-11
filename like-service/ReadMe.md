# Like Service

## Overview

This Like Service is a microservice written in Rust, providing gRPC APIs to manage likes on posts. It uses:

- **Tonic** for gRPC server and client
- **SurrealDB** as the database
- Async runtime with **Tokio**
- Structured logging with **Tracing**
- Configuration management with **config** crate
- Protobuf definitions compiled via **tonic-build**

---

## Features

- gRPC service exposing like operations
- Connects to User and Post microservices via gRPC clients
- Uses SurrealDB for storage with RocksDB or in-memory backend
- Graceful shutdown handling (Ctrl+C)
- Observability with logging and tracing
- Configuration through environment variables or config files

---

## Prerequisites

- Rust toolchain (recommended via [rustup](https://rustup.rs/))
- Docker (optional, for running SurrealDB)
- Protobuf compiler (`protoc`), typically included or installed separately

---

## Getting Started

### Clone the repository

```bash
git clone https://github.com/InsafNilam/word-weave
cd like-service
```

### Build the project

```bash
cargo build --release
```

### Run the server

```bash
cargo run --bin server
```

This starts the gRPC server on the configured address.

---

## Configuration

The service loads its configuration from environment variables or configuration files (e.g., `config.toml`).

Example environment variables:

```env
HOST=0.0.0.0
PORT=50051
DATABASE_URL=surrealdb://localhost:8000
USER_SERVICE_URL=http://user-service:50051
POST_SERVICE_URL=http://post-service:50051
LOG_LEVEL=info
```

You can customize host, port, database URL, and gRPC client URLs for User and Post services.

---

## Database

The service uses SurrealDB with either in-memory or RocksDB storage.

To run SurrealDB locally with Docker:

```bash
docker run -d --name like-db -p 8000:8000 surrealdb/surrealdb:latest
```

Connect with the CLI:

```bash
docker exec -it like-db surreal sql --conn ws://like-db:8000 --user root --pass YOUR_PASSWORD
```

---

## Protobuf Files

The service includes generated protobuf code under `src/proto` with these modules:

- `proto::like` - Like service proto definitions
- `proto::user` - User service client proto
- `proto::post` - Post service client proto

Protobuf files are compiled using `tonic-build` during the build process.

---

## Project Structure

```
like-service/
├── src/
│   ├── clients/          # gRPC clients for User, Post
│   ├── config.rs         # Configuration loader
│   ├── database.rs       # SurrealDB connection management
│   ├── error.rs          # Custom error types
│   ├── models.rs         # Domain models
│   ├── repository.rs     # Data repository layer
│   ├── service.rs        # gRPC service implementations
│   ├── main.rs           # Application entrypoint
│   └── proto/            # Generated protobuf code
├── Cargo.toml
└── README.md
```

---

## Graceful Shutdown

The server listens for Ctrl+C (SIGINT) and shuts down cleanly, closing connections properly.

---

## Logging and Tracing

Uses the `tracing` and `tracing-subscriber` crates for structured logging. Log level can be configured via environment variable.

---

## Useful Cargo Commands

- Build in release mode:

  ```bash
  cargo build --release
  ```

- Run tests:

  ```bash
  cargo test
  ```

- Format code:

  ```bash
  cargo fmt
  ```

- Check code for warnings/errors:

  ```bash
  cargo check
  ```

---

## Troubleshooting

- If `cargo build` hangs or locks on registry, try clearing cargo cache:

  ```bash
  rm -rf ~/.cargo/registry/index/*
  rm -rf ~/.cargo/.package-cache
  ```

- On Windows, setting `LIBCLANG_PATH` environment variable may fix build issues for some dependencies.

---

## References

- [Tonic gRPC Library](https://docs.rs/tonic/)
- [SurrealDB Documentation](https://surrealdb.com/docs)
- [Tokio Async Runtime](https://tokio.rs/)
- [Tracing Rust](https://tracing.rs/)
- [Package Repository](https://crates.io/)

---

## License

MIT License (or your preferred license)

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

---
