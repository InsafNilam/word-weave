# Microservices Architecture with Event-Driven Design & RabbitMQ

## Overview

This is a **polyglot microservices architecture** where each service uses different technology stacks and databases. The services are **fully decoupled** — no foreign key constraints between databases — communicating asynchronously via **RabbitMQ events** and synchronously via **gRPC**.

### Key Characteristics:

- **Tech Stack per Service:**
  - User Service: Node.js + MongoDB + gRPC
  - Post Service: Go + PostgreSQL + gRPC
  - Like Service: Rust + SurrealDB + RocksDB + gRPC
  - Media Service: Python + ImageKit + gRPC
  - Comment Service: .NET + MySQL + gRPC
  - Event Service: Ruby + PostgreSQL + RabbitMQ + Dead Letter Queue + gRPC
  - Frontend: Vite + React
  - API Gateway: Single entrypoint on port 8080
- **Event-Driven Architecture:**
  - Services publish/subscribe events through RabbitMQ
  - Event Service acts as central event publisher, consumer, event store, and dead letter queue handler
  - Redis used for caching/event state in Event Service
- **Decoupling:**
  - No direct DB foreign key relationships
  - Each service owns its data and DB schema
  - Inter-service communication via events and gRPC
- **Infrastructure:**
  - All services run in Docker containers managed by Docker Compose
  - Clean architecture principles applied per service
- **Webhook (in User Service):**
  - Runs on port 8081
  - Receives webhook events (e.g. user created, updated, deleted) via `svix` and `ngrok` for local dev/testing
  - Updates MongoDB accordingly

---

## Getting Started

### Prerequisites

- Docker (version 28.x+ recommended)
- Docker Compose (v2+)
- `ngrok` (for exposing local webhook server externally, optional)
- `curl` or Postman (for testing APIs)
- Internet connection for pulling images

### Environment Variables

Each service has its own `.env` file defining relevant configs like DB URLs, ports, RabbitMQ URLs, gRPC endpoints, API keys, etc.

Example `.env` variables for **User Service**:

```env
MONGO_URI=mongodb://mongo:27017/users
GRPC_PORT=50051
WEBHOOK_PORT=8081
SVIX_SECRET=your_svix_secret
NGROK_AUTH_TOKEN=your_ngrok_token
```

Make sure to set appropriate environment variables for all services before running.

---

## Running the System

Use Docker Compose to build and run all services:

```bash
docker-compose up -d --build
```

This will:

- Build images for all microservices
- Create containers and networks
- Start RabbitMQ, Redis, databases, API Gateway, and all microservices
- Services will connect to RabbitMQ and each other as configured

To rebuild and force recreate a specific service (e.g. like-service):

```bash
docker-compose up -d --no-deps --build --force-recreate like-service
```

---

## Webhook Setup (User Service)

1. Start the User Service container, which runs webhook on port 8081.
2. Use `ngrok` to expose local webhook port externally:

   ```bash
   ngrok http http://localhost:8081/
   ```

3. Copy the ngrok HTTPS URL.
4. Configure the webhook URL in your **Clerk dashboard** at:

   ```
   https://dashboard.clerk.com/apps/app_2zuiPbQaAsunxM80jB5wEoKBgmg/instances/ins_2zuiPoIi7pQ8f9U4aDAS5lx8Z7K/webhooks
   ```

5. Subscribe to user events (create, update, delete) to trigger webhook calls.
6. Webhook server updates MongoDB based on received events.

---

## Useful Docker Commands

- **List running containers:**

  ```bash
  docker ps
  ```

- **Inspect container details:**

  ```bash
  docker inspect <container_name_or_id>
  ```

- **Get container IP address:**

  ```bash
  docker inspect <container_name> | grep IPAddress
  ```

- **View container logs:**

  ```bash
  docker logs -f <container_name>
  ```

- **Enter running container shell:**

  ```bash
  docker exec -it <container_name> sh
  # or bash if available
  docker exec -it <container_name> bash
  ```

- **Stop containers:**

  ```bash
  docker-compose down
  ```

---

## Event Service Components

- **Event Publisher:** Publishes events to RabbitMQ exchanges/topics
- **Event Consumer:** Subscribes to relevant queues, processes events, and forwards them
- **Event Store:** (PostgreSQL) stores event history for auditing and replay
- **Dead Letter Queue Handler:** Handles failed events for retries or manual inspection
- **Redis Cache:** Optional, for caching event metadata or state
- **gRPC API:** For event replay, querying, and administration

---

## Architecture Diagram (Simplified)

```plaintext
+-------------+       +-------------+       +-------------+
|  User       |       |  Post       |       |  Like       |
|  (Node+Mongo) <---> |  (Go+PG)   <---> | (Rust+Surreal)|
+-------------+       +-------------+       +-------------+
       |                    |                      |
       +--------------------+----------------------+
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

- All services have **independent databases**, no shared schema or foreign keys.
- Services use **gRPC** for direct communication (internal RPC calls).
- All cross-service state changes are propagated via **RabbitMQ events**.
- Event-driven approach ensures eventual consistency and high decoupling.
- Using **Docker Compose** allows for easy local development and testing.
- Webhook setup with `svix` and `ngrok` enables external event triggers in local environments.
- Use logs and `docker exec` for debugging inside containers.
