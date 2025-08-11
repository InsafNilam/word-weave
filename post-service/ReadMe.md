# Post Service

## Overview

This is a high-performance gRPC microservice written in Go for managing posts. It uses:

- **gRPC** for inter-service communication
- **GORM** ORM with PostgreSQL backend
- Environment-based configuration with `.env` support
- Automatic database schema migration
- Structured project layout with modular components

---

## Prerequisites

- Go 1.24+ installed ([download](https://go.dev/dl/))
- PostgreSQL database running
- `protoc` Protocol Buffers compiler installed
- `protoc-gen-go` and `protoc-gen-go-grpc` plugins installed

---

## Setup

### 1. Clone the repository

```bash
git clone <repository-url>
cd post-service
```

### 2. Install Go dependencies

```bash
go mod tidy
```

### 3. Generate gRPC code from `.proto` files

```bash
protoc --go_out=. --go-grpc_out=. protos/post.proto
```

Make sure `protoc` and plugins are installed and available in your `PATH`.

---

## Configuration

Create a `.env` file in the root directory with required environment variables:

```env
APP_ENV=development
DATABASE_URL=postgres://user:password@localhost:5432/postdb?sslmode=disable
GRPC_HOST=0.0.0.0
GRPC_PORT=50051
```

Alternatively, set environment variables directly.

---

## Build and Run

### Build

```bash
go build -o bin/post-service main.go
```

### Run

```bash
./bin/post-service
```

On startup, the service will:

- Load configuration (from `.env` or environment)
- Connect to the PostgreSQL database
- Automatically migrate the `posts` table schema
- Start the gRPC server on configured host and port

---

## Project Structure

```
post-service/
├── cmd/                   # Optional: main application entrypoints
├── config/                # Configuration loader
├── database/              # Database connection logic
├── models/                # GORM models (e.g., Post)
├── protos/                # Protocol Buffer definitions
├── server/                # gRPC server setup and handlers
├── main.go                # Application bootstrap
├── go.mod                 # Go module definition
└── go.sum                 # Go module checksums
```

---

## Dependencies

- `google.golang.org/grpc` - gRPC framework for Go
- `gorm.io/gorm` and `gorm.io/driver/postgres` - ORM and Postgres driver
- `github.com/joho/godotenv` - Loads `.env` files for local development
- `github.com/lib/pq` - PostgreSQL driver for database/sql

---

## Tips & Troubleshooting

- Make sure PostgreSQL is running and accessible with the connection string in `.env`.

- If schema migrations fail, check your database permissions.

- To generate protobuf files, ensure `protoc` and Go plugins (`protoc-gen-go` and `protoc-gen-go-grpc`) are installed:

  ```bash
  go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
  ```

- Add `$GOPATH/bin` to your system `PATH` if `protoc-gen-go` or `protoc-gen-go-grpc` is not found.

---

## Running with Docker (Optional)

You can containerize this service with a Dockerfile and use Docker Compose to spin up alongside PostgreSQL.

---

## References

- [gRPC in Go](https://grpc.io/docs/languages/go/)
- [GORM](https://gorm.io/)
- [godotenv](https://github.com/joho/godotenv)

---

## License

MIT License (or your preferred license)

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

```

```
