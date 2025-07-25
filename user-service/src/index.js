import dotenv from "dotenv";
dotenv.config();

import mongoose from "mongoose";
import {
  createWebhookServer,
  startWebhookServer,
  closeWebhookServer,
  getServerInfo,
} from "./servers/webhook-server.js";
import { startGrpcServer } from "./servers/grpc-server.js";

async function startApplication() {
  let webhookServer = null;
  let grpcServer = null;

  try {
    console.log("🚀 Starting application...");

    // 1. Connect to MongoDB first
    console.log("📦 Connecting to MongoDB...");
    await mongoose.connect(process.env.MONGO_URI, {
      maxPoolSize: 10,
      serverSelectionTimeoutMS: 5000,
      socketTimeoutMS: 45000,
      bufferCommands: false,
    });
    console.log("✅ Connected to MongoDB");

    // 2. Create and start webhook server
    console.log("🌐 Starting webhook server...");
    const webhookApp = createWebhookServer();
    webhookServer = await startWebhookServer(webhookApp);

    // Log webhook server info
    const webhookInfo = getServerInfo(webhookServer);
    console.log(`📡 Webhook server info:`, webhookInfo);

    // 3. Start gRPC server
    console.log("⚡ Starting gRPC server...");
    grpcServer = await startGrpcServer();

    console.log("🎉 All services started successfully!");
    console.log("📊 Application is ready to handle requests");
  } catch (error) {
    console.error("❌ Failed to start application:", error);

    // Cleanup on startup failure
    await cleanup(webhookServer, grpcServer);
    process.exit(1);
  }

  // Setup graceful shutdown handlers
  setupGracefulShutdown(webhookServer, grpcServer);
}

/**
 * Setup graceful shutdown handlers for different signals
 */
function setupGracefulShutdown(webhookServer, grpcServer) {
  const shutdown = async (signal) => {
    console.log(`\n🛑 Received ${signal}. Initiating graceful shutdown...`);

    try {
      await cleanup(webhookServer, grpcServer);
      console.log("✅ Graceful shutdown completed");
      process.exit(0);
    } catch (error) {
      console.error("❌ Error during shutdown:", error);
      process.exit(1);
    }
  };

  // Handle different shutdown signals
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGUSR2", () => shutdown("SIGUSR2")); // For nodemon

  // Handle uncaught exceptions
  process.on("uncaughtException", (error) => {
    console.error("❌ Uncaught Exception:", error);
    shutdown("uncaughtException");
  });

  // Handle unhandled promise rejections
  process.on("unhandledRejection", (reason, promise) => {
    console.error("❌ Unhandled Rejection at:", promise, "reason:", reason);
    shutdown("unhandledRejection");
  });
}

/**
 * Cleanup function to properly close all connections
 */
async function cleanup(webhookServer, grpcServer) {
  const cleanupTasks = [];

  // Close webhook server
  if (webhookServer) {
    console.log("🔌 Closing webhook server...");
    cleanupTasks.push(
      closeWebhookServer(webhookServer, 5000).catch((err) => {
        console.error("❌ Error closing webhook server:", err);
      })
    );
  }

  // Close gRPC server
  if (grpcServer) {
    console.log("⚡ Closing gRPC server...");
    cleanupTasks.push(
      new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error("gRPC server shutdown timeout"));
        }, 5000);

        grpcServer.tryShutdown((err) => {
          clearTimeout(timeout);
          if (err) {
            console.error("❌ Error closing gRPC server:", err);
            reject(err);
          } else {
            console.log("✅ gRPC server closed successfully");
            resolve();
          }
        });
      }).catch((err) => {
        console.error("❌ gRPC server shutdown error:", err);
        // Force shutdown if graceful shutdown fails
        grpcServer.forceShutdown();
      })
    );
  }

  // Close MongoDB connection
  if (mongoose.connection.readyState === 1) {
    console.log("📦 Closing MongoDB connection...");
    cleanupTasks.push(
      mongoose.connection.close().catch((err) => {
        console.error("❌ Error closing MongoDB connection:", err);
      })
    );
  }

  // Wait for all cleanup tasks to complete
  try {
    await Promise.allSettled(cleanupTasks);
    console.log("🧹 Cleanup completed");
  } catch (error) {
    console.error("❌ Error during cleanup:", error);
  }
}

startApplication().catch((error) => {
  console.error("❌ Application startup failed:", error);
  process.exit(1);
});
