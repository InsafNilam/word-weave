# API Gateway

## Overview

This project is an **API Gateway** for routing requests to multiple microservices, including users, posts, likes, comments, events, and media services. It uses Express.js with middleware such as CORS, body-parser, and authentication through Clerk. The gateway also supports gRPC integration.

---

## Features

- Route requests to microservices via REST endpoints:
  - `/api/users`
  - `/api/posts`
  - `/api/likes`
  - `/api/comments`
  - `/api/events`
  - `/api/media`
- Middleware integration: CORS, body-parser
- Authentication support with Clerk (`@clerk/express`)
- gRPC client integration with `@grpc/grpc-js` and `@grpc/proto-loader`
- Environment variable support with `dotenv`
- Development mode with `nodemon` for auto-reloading

---

## Prerequisites

- Node.js v18 or newer
- npm or yarn package manager
- Access to microservices endpoints for the routed paths
- Clerk account and configuration (if using Clerk authentication)
- `.env` file setup with necessary environment variables (e.g., Clerk keys)

---

## Installation

```bash
git clone https://github.com/InsafNilam/word-weave
cd api-gateway
npm install
```

---

## Usage

### Development mode (with auto-reload):

```bash
npm run dev
```

### Production mode:

```bash
npm start
```

The server runs by default on port 3000 (or the port specified in your environment variables).

---

## Project Structure

```
api-gateway/
├── src/
│   ├── index.js          # Main entry point
│   ├── routes/
│   │   ├── users.js      # User routes
│   │   ├── posts.js      # Post routes
│   │   ├── likes.js      # Like routes
│   │   ├── comments.js   # Comment routes
│   │   ├── events.js     # Event routes
│   │   └── media.js      # Media routes
├── package.json
├── README.md
└── .env                  # Environment variables (not committed)
```

---

## Environment Variables

Create a `.env` file in the root directory to configure:

```dotenv
PORT=3000
CLERK_PUBLISHABLE_KEY=your_clerk_publishable_key
CLERK_SECRET_KEY=your_clerk_secret_key
# Add other environment variables here
```

---

## Dependencies

- `express` - Web framework
- `cors` - Enable Cross-Origin Resource Sharing
- `body-parser` - Parse incoming JSON requests
- `@clerk/express` - Clerk authentication middleware
- `@grpc/grpc-js` and `@grpc/proto-loader` - gRPC client tools
- `dotenv` - Load environment variables

---

## Development

- Use `nodemon` for automatic server restarts on file changes.
- Add your routes inside `src/routes` and import in `src/index.js`.

---

## Testing

No test suite is configured yet.

---

## Contributing

Feel free to open issues or submit pull requests for improvements.

---

## License

ISC License

## Contact

For questions, contact \[[insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)]
