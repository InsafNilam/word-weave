import dotenv from "dotenv";
dotenv.config();

import path from "path";
import grpc from "@grpc/grpc-js";
import { fileURLToPath } from "url";
import protoLoader from "@grpc/proto-loader";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROTO_PATH = path.join(__dirname, "../protos/media.proto");

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});

const proto = grpc.loadPackageDefinition(packageDef).media;

export const mediaClient = new proto.MediaService(
  process.env.MEDIA_SERVICE_HOST || "media-service:50051",
  grpc.credentials.createInsecure()
);
