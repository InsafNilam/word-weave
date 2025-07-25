import dotenv from "dotenv";
dotenv.config();

import grpc from "@grpc/grpc-js";
import { createGrpcServer } from "../grpc/server.js";

export const startGrpcServer = () => {
  const PORT = process.env.GRPC_PORT || "50051";
  const ADDRESS = `0.0.0.0:${PORT}`;
  const server = createGrpcServer();

  return new Promise((resolve, reject) => {
    server.bindAsync(
      ADDRESS,
      grpc.ServerCredentials.createInsecure(),
      (err, port) => {
        if (err) {
          console.error("❌ Failed to start gRPC server:", err);
          reject(err);
          return;
        }

        console.log(`🚀 gRPC server running at ${ADDRESS}`);
        resolve(server);
      }
    );
  });
};
