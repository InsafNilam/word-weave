# Polyglot Microservices Architecture with Event-Driven Design & RabbitMQ (WordWeave)

## Overview

This repository demonstrates a **polyglot microservices architecture** designed for scalability, flexibility, and decoupling. Each service is built using different technology stacks and databases, communicating asynchronously via **RabbitMQ events** and synchronously via **gRPC**.

### Key Features

- **Fully Decoupled Services**  
  Each microservice owns its own database and schema with no shared foreign key constraints. Services communicate through asynchronous events and synchronous gRPC calls.

- **Event-Driven Architecture with RabbitMQ**  
  Services publish and subscribe to domain events for eventual consistency and loose coupling.

- **Polyglot Stack**  
  Different services leverage the best tools for their purpose:

  - **User Service:** Node.js + MongoDB
  - **Post Service:** Go + PostgreSQL
  - **Like Service:** Rust + SurrealDB + RocksDB
  - **Media Service:** Python + ImageKit
  - **Comment Service:** .NET + MySQL
  - **Event Service:** Ruby + PostgreSQL + RabbitMQ + Redis (Event Store + Dead Letter Queue)
  - **Frontend:** React + Vite
  - **API Gateway:** Single unified entrypoint (port `8080`)

- **Centralized Event Service**  
  Core event publisher, consumer, event store, and dead letter queue handler.

- **Dockerized for Easy Local Development**  
  All services run in isolated Docker containers orchestrated by Docker Compose.

---

## Getting Started

### Prerequisites

- Docker **20.x+**
- Docker Compose **v2+**
- `ngrok` (optional — for exposing local webhook server externally)
- `curl` or Postman (for API testing)
- Internet connection (for pulling images)

---

## Environment Variables

Each service has its own `.env` file with configs like DB URLs, ports, RabbitMQ URLs, gRPC endpoints, API keys, etc.

Example `.env` for **User Service**:

```env
CLERK_PUBLISHABLE_KEY=${CLERK_PUBLISHABLE_KEY}
CLERK_SECRET_KEY=${CLERK_SECRET_KEY}
CLERK_WEBHOOK_SIGNING_SECRET=${CLERK_WEBHOOK_SIGNING_SECRET}
GRPC_PORT=50051
WEBHOOK_PORT=${WEBHOOK_PORT}
WEBHOOK_HOST=${WEBHOOK_HOST}
MONGO_URI=mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@user-db:27017/user_db
ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
EVENT_SERVICE_HOST=${EVENT_SERVICE_ADDR}
```
---

## Running the System

To start **all services**:

```bash
docker-compose up -d --build
```

This will:

- Build all images
- Create networks and containers
- Start RabbitMQ, Redis, databases, API Gateway, and all microservices

To rebuild only one service:

```bash
docker-compose up -d --no-deps --build --force-recreate like-service
```

---

## Webhook Setup (User Service)

1. Start **User Service** container (webhook listens on `8081`)
2. Run `ngrok`:

   ```bash
   ngrok http http://localhost:8081/
   ```

3. Copy the HTTPS ngrok URL add the suffix /webhook/clerk , and then paste the complete URL into the **user events** webhooks
4. Add `CLERK_WEBHOOK_SIGNING_SECRET` from Clerk to your `.env`
5. Restart **User Service**
6. Incoming webhooks will update MongoDB automatically

---

## Event Service Components

- **Event Publisher:** Publishes events to RabbitMQ
- **Event Consumer:** Subscribes & processes events
- **Event Store:** PostgreSQL-based event history
- **Dead Letter Queue Handler:** Retry & inspect failed events
- **Redis Cache:** Optional for metadata caching
- **gRPC API:** Replay, query, and admin control

---

## Authorization & Validation

- **Authentication:** API Gateway (token validation)
- **Authorization:** Service-level via gRPC validation (e.g., user exists before creating post)
- **Events:** Used for eventual consistency — not immediate validation

---

## Useful Docker Commands

```bash
# List running containers
docker ps

# Inspect container details
docker inspect <container_name_or_id>

# Get container IP
docker inspect <container_name> | grep IPAddress

# View logs
docker logs -f <container_name>

# Enter container shell
docker exec -it <container_name> sh
docker exec -it <container_name> bash

# Stop all containers
docker-compose down
```

---

## Database Access & Debugging

**MongoDB (User Service):**

```bash
docker exec -it user-db mongosh -u mongo -p v3jjS70vmYmB --authenticationDatabase admin
use user_db
db.users.find().pretty()
```

**PostgreSQL (Post Service):**

```bash
docker exec -it post-db sh
psql -U postgres -d post_db
```

**SurrealDB (Like Service):**

```bash
# Download SurrealDB CLI: https://github.com/surrealdb/surrealdb/releases
./surreal sql --conn http://localhost:8000 --user root --pass A473nuaWrUvn
USE NAMESPACE likes_service DATABASE likes;
```

**MySQL (Comment Service):**

```bash
docker exec -it comment-db sh
mysql -u root -p
USE comment_db;
SHOW TABLES;
SELECT * FROM <table_name>;
```

---

## Architecture Diagram

```plaintext
+--------------+       +-------------+       +---------------+       +---------------+
|  User        |       |  Post       |       |  Like         |       |    Comment    |
|  (Node+Mongo)| <---> |  (Go+PG)    | <---> | (Rust+Surreal)| <---> |  (.Net+MySQL) |
+--------------+       +-------------+       +---------------+       +---------------+
       |                    |                       |                    |
       +--------------------+-----------------------+--------------------+
                                        |
                                RabbitMQ (Event Bus)
                                        |
                      +-------------------------------------+
                      |             Event Service           |
                      | (Ruby + RabbitMQ + PG + DLQ + Redis)|
                      +-------------------------------------+
                                        |
                                    API Gateway
                                        |
                                  Frontend (React)
```

---

## Notes

- All services have **independent databases**
- **gRPC** for direct service-to-service communication
- **RabbitMQ events** for async, decoupled workflows
- **Docker Compose** for local dev & testing
- **Ngrok + Clerk** for local webhook testing

---

## Contributing

Pull requests welcome! Fork & submit PRs with improvements.

---

## License

MIT License

---

## Contact

Open an issue or contact the maintainer for questions.

```
