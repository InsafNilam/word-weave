import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import webhookRoutes from "./webhook/index.js";
import mongoose from "mongoose";

import grpc from "@grpc/grpc-js";
import { createGrpcServer } from "./server.js";

dotenv.config();

const app = express();

app.use(cors());
app.use("/webhook", webhookRoutes); // Exposed as /webhook/clerk

const WEBHOOK_PORT = process.env.WEBHOOK_PORT || 8001;

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    console.log("✅ Connected to MongoDB");

    app.listen(WEBHOOK_PORT, () => {
      console.log(
        `🚀 Webhook server listening at http://localhost:${WEBHOOK_PORT}`
      );
    });
  })
  .catch((err) => {
    console.error("❌ MongoDB connection error:", err);
  });

const PORT = process.env.GRPC_PORT || "50051";
const ADDRESS = `0.0.0.0:${PORT}`;
const server = createGrpcServer();

server.bindAsync(
  ADDRESS,
  grpc.ServerCredentials.createInsecure(),
  (err, port) => {
    if (err) {
      console.error("❌ Failed to start gRPC server:", err);
      process.exit(1);
    }

    console.log(`🚀 gRPC server running at ${ADDRESS}`);
    // server.start();
  }
);

process.on("SIGINT", () => {
  console.log("\n🛑 Received SIGINT. Shutting down gRPC server...");
  server.tryShutdown((err) => {
    if (err) {
      console.error("❌ Error during shutdown:", err);
      process.exit(1);
    }
    console.log("✅ gRPC server stopped gracefully.");
    process.exit(0);
  });
});
