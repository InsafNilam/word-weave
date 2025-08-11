import dotenv from "dotenv";
dotenv.config();

import express from "express";
import mongoose from "mongoose";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import webhookRoutes from "../webhook/index.js";

/**
 * Creates and configures the Express webhook server
 * @returns {Express} Configured Express application
 */
export const createWebhookServer = () => {
  const app = express();

  // Security middleware
  app.use(
    helmet({
      contentSecurityPolicy: false, // Disable CSP for webhooks
    })
  );

  // CORS configuration
  app.use(
    cors({
      origin: process.env.ALLOWED_ORIGINS?.split(",") || "*",
      methods: ["POST", "GET"],
      allowedHeaders: [
        "Content-Type",
        "svix-id",
        "svix-timestamp",
        "svix-signature",
      ],
    })
  );

  // Rate limiting for webhook endpoints
  const webhookLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: {
      error: "Too many webhook requests from this IP, please try again later.",
    },
    standardHeaders: true,
    legacyHeaders: false,
  });

  // Apply rate limiting to webhook routes
  app.use("/webhook", webhookLimiter);

  // Health check endpoint
  app.get("/health", (req, res) => {
    res.status(200).json({
      status: "healthy",
      service: "user-server",
      timestamp: new Date().toISOString(),
      services: {
        mongodb:
          mongoose.connection.readyState === 1 ? "connected" : "disconnected",
        uptime: process.uptime(),
        memory: process.memoryUsage(),
      },
    });
  });

  // Webhook routes
  app.use("/webhook", webhookRoutes);

  // Global error handler
  app.use((err, req, res, next) => {
    console.error("❌ Webhook server error:", err);

    // Don't leak error details in production
    const isDevelopment = process.env.NODE_ENV === "development";

    res.status(err.status || 500).json({
      success: false,
      message: isDevelopment ? err.message : "Internal server error",
      ...(isDevelopment && { stack: err.stack }),
    });
  });

  // Handle 404 for unmatched routes
  app.all("/{*any}", (req, res) => {
    res.status(404).json({
      success: false,
      message: "Endpoint not found",
      path: req.originalUrl,
    });
  });

  return app;
};

/**
 * Starts the webhook server with proper error handling and graceful shutdown
 * @param {Express} app - The Express application to start
 * @returns {Promise<Server>} Promise that resolves to the HTTP server instance
 */
export const startWebhookServer = (app) => {
  const WEBHOOK_PORT = process.env.WEBHOOK_PORT || 8081;
  const HOST = process.env.WEBHOOK_HOST || "localhost";

  return new Promise((resolve, reject) => {
    // Handle port already in use
    app.on("error", (err) => {
      if (err.code === "EADDRINUSE") {
        console.error(`❌ Port ${WEBHOOK_PORT} is already in use`);
        reject(new Error(`Port ${WEBHOOK_PORT} is already in use`));
      } else {
        console.error("❌ Webhook server error:", err);
        reject(err);
      }
    });

    const server = app.listen(WEBHOOK_PORT, HOST, () => {
      console.log(
        `🚀 Webhook server listening at http://${HOST}:${WEBHOOK_PORT}`
      );
      console.log(
        `📊 Health check available at http://${HOST}:${WEBHOOK_PORT}/health`
      );
      // Resolve the promise with the server instance
      resolve(server);
    });

    // Handle server startup errors
    server.on("error", (err) => {
      if (err.code === "EADDRINUSE") {
        console.error(`❌ Port ${WEBHOOK_PORT} is already in use`);
        reject(new Error(`Port ${WEBHOOK_PORT} is already in use`));
      } else {
        console.error("❌ Failed to start webhook server:", err);
        reject(err);
      }
    });

    // Handle server listening event
    server.on("listening", () => {
      const address = server.address();
      console.log(
        `📡 Webhook server bound to ${address.address}:${address.port}`
      );
    });

    // Handle connection events for monitoring
    let connections = 0;
    server.on("connection", (socket) => {
      connections++;
      console.log(`🔗 New connection established. Total: ${connections}`);

      socket.on("close", () => {
        connections--;
        console.log(`🔌 Connection closed. Total: ${connections}`);
      });
    });

    // Graceful shutdown handler
    const gracefulShutdown = () => {
      console.log("🛑 Webhook server shutting down gracefully...");

      server.close((err) => {
        if (err) {
          console.error("❌ Error during webhook server shutdown:", err);
          process.exit(1);
        }
        console.log("✅ Webhook server closed successfully");
      });
    };

    // Handle shutdown signals
    process.on("SIGTERM", gracefulShutdown);
    process.on("SIGINT", gracefulShutdown);
  });
};

/**
 * Alternative function to start webhook server with additional configuration
 * @param {Object} options - Configuration options
 * @param {number} options.port - Server port
 * @param {string} options.host - Server host
 * @param {boolean} options.enableLogging - Enable request logging
 * @returns {Promise<{app: Express, server: Server}>}
 */
export const startWebhookServerWithOptions = async (options = {}) => {
  const {
    port = process.env.WEBHOOK_PORT || 8001,
    host = process.env.WEBHOOK_HOST || "localhost",
    enableLogging = process.env.NODE_ENV === "development",
  } = options;

  const app = createWebhookServer();

  // Optional request logging
  if (enableLogging) {
    app.use((req, res, next) => {
      const start = Date.now();
      const originalSend = res.send;

      res.send = function (data) {
        const duration = Date.now() - start;
        console.log(
          `📝 ${req.method} ${req.path} - ${res.statusCode} (${duration}ms)`
        );
        originalSend.call(this, data);
      };

      next();
    });
  }

  try {
    const server = await new Promise((resolve, reject) => {
      const serverInstance = app.listen(port, host, () => {
        console.log(
          `🚀 Webhook server with options listening at http://${host}:${port}`
        );
        resolve(serverInstance);
      });

      serverInstance.on("error", reject);
    });

    return { app, server };
  } catch (error) {
    console.error("❌ Failed to start webhook server with options:", error);
    throw error;
  }
};

// Export additional utilities
export const getServerInfo = (server) => {
  if (!server || !server.listening) {
    return null;
  }

  const address = server.address();
  return {
    host: address.address,
    port: address.port,
    family: address.family,
    listening: server.listening,
  };
};

export const closeWebhookServer = (server, timeout = 10000) => {
  return new Promise((resolve, reject) => {
    if (!server) {
      resolve();
      return;
    }

    console.log("🛑 Closing webhook server...");

    // Set a timeout for forceful shutdown
    const forceTimeout = setTimeout(() => {
      console.log("⚠️ Forcefully closing webhook server...");
      server.destroy ? server.destroy() : server.close();
      reject(new Error("Server shutdown timeout"));
    }, timeout);

    server.close((err) => {
      clearTimeout(forceTimeout);
      if (err) {
        console.error("❌ Error closing webhook server:", err);
        reject(err);
      } else {
        console.log("✅ Webhook server closed successfully");
        resolve();
      }
    });
  });
};
