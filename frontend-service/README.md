# Frontend Service (Vite + React)

## Overview

This is the frontend client for your microservices architecture, built with React and Vite. It communicates with backend services (such as User Service) via REST or gRPC-web.

---

## Features

- Fast development with Vite's hot module replacement (HMR)
- React 18+ with functional components and hooks
- Configurable environment variables for API endpoints
- Supports Docker-based deployment with dynamic env injection
- Uses `.env` files for local dev and runtime env vars for production

---

## Prerequisites

- Node.js 18+
- Docker (optional, for containerized deployment)

---

## Setup and Development

### 1. Clone the repository

```bash
git clone <your-frontend-repo-url>
cd frontend-service
```

### 2. Install dependencies

```bash
npm install
```

### 3. Environment variables

Vite loads environment variables from `.env` files starting with `VITE_`. For example:

```
VITE_API_URL=http://localhost:5000/api
```

Create a `.env` file in your project root:

```bash
touch .env
```

Example `.env`:

```env
VITE_USER_SERVICE_URL=http://localhost:50052
VITE_API_BASE_URL=http://localhost:5000/api
```

### 4. Run development server

```bash
npm run dev
```

Open your browser at `http://localhost:5173`

---

## Using Environment Variables in Code

Access variables prefixed with `VITE_` via `import.meta.env`:

```js
const userServiceUrl = import.meta.env.VITE_USER_SERVICE_URL;
```

---

## Dockerization with Dynamic Env Injection

By default, Vite statically injects env vars at build time. To set env vars dynamically at container runtime:

- [Dynamic Environment Variables with Vite and Docker](https://dev.to/dutchskull/setting-up-dynamic-environment-variables-with-vite-and-docker-5cmj)

---

## Dockerfile Example

```Dockerfile
# Build stage
FROM node:18-alpine AS build

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

---

## Scripts

| Command           | Description                  |
| ----------------- | ---------------------------- |
| `npm run dev`     | Run development server (HMR) |
| `npm run build`   | Build for production         |
| `npm run preview` | Preview production build     |

---

## Troubleshooting

- Ensure environment variables start with `VITE_` to be injected by Vite.
- If env vars do not update in Docker, confirm your runtime injection strategy.
- Ports: Dev server usually runs on `5173`; ensure no conflicts.
- React app fetch failures: Check CORS and API URLs.

---

## License

MIT (or your preferred license)

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

```

```
