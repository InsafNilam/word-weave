export const config = {
  webhook: {
    port: process.env.WEBHOOK_PORT || 8001,
    clerkSecret: process.env.CLERK_WEBHOOK_SIGNING_SECRET,
  },
  grpc: {
    port: process.env.GRPC_PORT || "50051",
    address: "0.0.0.0",
  },
  database: {
    uri: process.env.MONGO_URI,
  },
};
