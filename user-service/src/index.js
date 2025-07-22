import grpc from "@grpc/grpc-js";
import { createGrpcServer } from "./server.js";

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
