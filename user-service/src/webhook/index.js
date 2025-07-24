import express from "express";
import bodyParser from "body-parser";
import { clerkWebHook } from "./clerk.js";

const router = express.Router();

// Raw body parser required by Clerk/Svix
router.post(
  "/clerk",
  bodyParser.raw({ type: "application/json" }),
  clerkWebHook
);

export default router;
