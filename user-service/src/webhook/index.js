import express from "express";
import bodyParser from "body-parser";
import { clerkWebHook } from "./clerk.js";

const router = express.Router();

// Add request size limit and validation
router.post(
  "/clerk",
  bodyParser.raw({
    type: "application/json",
    limit: "10mb",
  }),
  (req, res, next) => {
    if (!req.body || req.body.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Request body is required",
      });
    }
    next();
  },
  clerkWebHook
);

export default router;
