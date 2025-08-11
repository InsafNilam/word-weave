# Event Service (Ruby)

## Overview

This is a Ruby-based Event Service microservice that handles event processing with gRPC, PostgreSQL, RabbitMQ, and background consumers. It uses:

- **gRPC** for inter-service communication
- **Sequel** ORM with PostgreSQL
- **Bunny** for RabbitMQ messaging
- **Dry-rb** libraries for validations and data structures
- **Redis** for caching/state
- **Dotenv** for environment configuration

---

## Prerequisites

- Ruby (>= 3.0 recommended)
- PostgreSQL
- RabbitMQ
- Redis
- [MSYS2](https://www.msys2.org/) (for Windows users to build native gems)
- Docker Desktop (optional for containerized environment)

---

## Setup

### 1. Install dependencies

```bash
bundle install
```

If you have native gem compilation issues on Windows, install MSYS2 and required toolchains:

```bash
ridk install
pacman -Syu
pacman -S base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-postgresql
```

Make sure to add `C:\msys64\mingw64\bin` to your PATH environment variable.

---

### 2. Environment variables

Create a `.env` file with:

```env
DATABASE_URL=postgres://user:password@localhost:5432/event_service_db
GRPC_PORT=50055
GRPC_HOST=0.0.0.0
LOG_LEVEL=INFO
DEBUG=false
RABBITMQ_URL=amqp://guest:guest@localhost:5672
REDIS_URL=redis://localhost:6379
```

---

### 3. Protocol Buffer Compilation

Generate Ruby gRPC code from proto files:

```bash
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/eventpb --grpc_out=lib/grpc/eventpb protos/event.proto
grpc_tools_ruby_protoc -I protos --ruby_out=lib/grpc/commentpb --grpc_out=lib/grpc/commentpb protos/comment.proto
```

Adjust paths according to your project structure.

---

## Running the Service

### Available commands:

```bash
ruby lib/main.rb setup          # Set up DB and run migrations
ruby lib/main.rb server         # Start gRPC server
ruby lib/main.rb consumer       # Start event consumer
ruby lib/main.rb dead_letter    # Start dead letter queue handler
ruby lib/main.rb all            # Run all components
ruby lib/main.rb help           # Show usage
```

---

## Development Notes

- Use `rspec` for testing.
- Use `rubocop` for code linting.
- FactoryBot and DatabaseCleaner are included for test data and cleanup.
- Use `pry` for debugging sessions.
- Use `dotenv` to manage environment variables.
- Logging is handled via the standard Ruby `Logger` gem.

---

## Troubleshooting

- **Docker error on Windows**:
  If you see `docker: error during connect: ... The system cannot find the file specified`, ensure Docker Desktop is running.

- **Native gem compilation failures on Windows**:
  Install MSYS2 and required development tools as described above.

---

## Useful Commands

```bash
bundle info <gem-name>        # Info about installed gem (https://rubygems.org/)
gem env                       # RubyGems environment info
gem install <gem-name>        # Install gem manually
bundle lock --add-platform x86_64-linux   # Add Linux platform for cross-compatibility
```

---

## Resources

- [MSYS2 Installation](https://www.msys2.org/)
- [Sequel ORM Documentation](https://sequel.jeremyevans.net/)
- [gRPC Ruby Quickstart](https://grpc.io/docs/languages/ruby/quickstart/)
- [Bunny (RabbitMQ Client)](https://github.com/ruby-amqp/bunny)
- [Dry-rb Documentation](https://dry-rb.org/)

---

## License

MIT License (or your preferred license)

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

---
