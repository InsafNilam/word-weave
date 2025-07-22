import dotenv from "dotenv";
dotenv.config();

import path from "path";
import grpc from "@grpc/grpc-js";
import { fileURLToPath } from "url";
import protoLoader from "@grpc/proto-loader";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROTO_PATH = path.join(__dirname, "../protos/post.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});

const proto = grpc.loadPackageDefinition(packageDef).post;

export const postClient = new proto.PostService(
  process.env.POST_SERVICE_HOST || "post-service:50052",
  grpc.credentials.createInsecure()
);
