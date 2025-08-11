# User Service

## Overview

User Service is a Node.js microservice responsible for user management in a microservices architecture. It exposes:

- **gRPC server** for internal communication
- **HTTP webhook endpoint** to handle Clerk webhook events securely
- **MongoDB** for persistent user data storage
- **Graceful startup and shutdown** with proper resource cleanup
- **Security** features including request verification using webhook signing secrets

---

## Features

- Verify incoming webhook requests using `svix` to ensure authenticity
- Process user lifecycle events (`user.created`, `user.updated`, `user.deleted`)
- Connect to MongoDB with optimized pooling and timeout settings
- Runs both webhook HTTP server and gRPC server concurrently
- Robust error handling and graceful shutdown on signals (`SIGINT`, `SIGTERM`, etc.)
- Environment-driven configuration using `.env`

---

## Prerequisites

- Node.js 18+
- MongoDB database accessible via connection URI
- Clerk account with webhook signing secret for event verification
- `protoc` and `grpc-tools` for gRPC code generation (if modifying proto files)

---

## Setup

### 1. Clone the repository

```bash
git clone <repository-url>
cd user-service
```

### 2. Install dependencies

```bash
npm install
```

### 3. Create `.env` file

```env
MONGO_URI=mongodb://username:password@host:port/dbname
CLERK_WEBHOOK_SIGNING_SECRET=<your_clerk_webhook_secret>
GRPC_HOST=0.0.0.0
GRPC_PORT=50052
```

### 4. Start the service

- For production:

  ```bash
  npm start
  ```

- For development (with live reload):

  ```bash
  npm run dev
  ```

---

## Webhook Endpoint

- **URL:** `/webhook/clerk`
- **Method:** POST
- **Purpose:** Receives and verifies Clerk webhook events
- **Events handled:**

  - `user.created` — creates a new user record
  - `user.updated` — updates existing user data
  - `user.deleted` — deletes user data

- Verification is performed using the `svix` package and your webhook signing secret.

---

## gRPC Server

- Runs on configured `GRPC_HOST:GRPC_PORT`
- Provides RPC methods for user operations (refer to `.proto` files in `/protos`)
- Uses `@grpc/grpc-js` and `@grpc/proto-loader`

---

## Application Lifecycle

- Connects to MongoDB with pooling and timeouts
- Starts webhook HTTP server and gRPC server concurrently
- Handles graceful shutdown on signals (`SIGINT`, `SIGTERM`, `SIGUSR2`)
- Cleans up MongoDB connections and closes servers properly

---

## Project Structure

```
user-service/
├── src/
│   ├── servers/
│   │   ├── grpc-server.js       # gRPC server implementation
│   │   └── webhook-server.js    # Express webhook server implementation
│   ├── services/
│   │   └── user.handler.js      # Business logic for user webhook events
│   ├── protos/                  # gRPC protobuf definitions
│   ├── grpc/                    # Generated gRPC client and server code
│   └── index.js                 # Main entry point bootstrapping the app
├── .env                        # Environment variables (not committed)
├── package.json
└── README.md
```

---

## Troubleshooting

- **MongoDB connection issues:** Check your `MONGO_URI` and network connectivity.
- **Webhook verification failures:** Ensure the `CLERK_WEBHOOK_SIGNING_SECRET` matches your Clerk dashboard secret.
- **Ports in use:** Verify that configured ports are free or update `.env` accordingly.
- **Unhandled rejections/exceptions:** Service will attempt graceful shutdown; check logs for root cause.

---

## Development Tips

- Use `nodemon` for live-reloading during development (`npm run dev`)

- Modify proto files and regenerate gRPC code using:

  ```bash
  npx grpc_tools_node_protoc --js_out=import_style=commonjs,binary:./src/grpc \
    --grpc_js_out=./src/grpc \
    --proto_path=./src/protos ./src/protos/*.proto
  ```

- Add tests and improve error handling as needed

---

## License

MIT License (or your preferred license)

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)
