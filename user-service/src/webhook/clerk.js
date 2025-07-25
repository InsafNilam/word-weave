import dotenv from "dotenv";
dotenv.config();

import { Webhook } from "svix";
import { UserHandler } from "../services/user.handler.js";

const WEBHOOK_SECRET = process.env.CLERK_WEBHOOK_SIGNING_SECRET;

if (!WEBHOOK_SECRET) {
  throw new Error(
    "CLERK_WEBHOOK_SIGNING_SECRET environment variable is required"
  );
}

export const clerkWebHook = async (req, res) => {
  try {
    const payload = req.body;
    const headers = req.headers;

    const wh = new Webhook(WEBHOOK_SECRET);
    let evt;

    try {
      evt = wh.verify(payload, headers);
    } catch (err) {
      console.error("❌ Webhook verification failed:", err);
      return res.status(400).json({
        success: false,
        message: "Webhook verification failed",
      });
    }

    console.log(`📥 Received webhook: ${evt.type} for user ${evt.data.id}`);

    // Handle different webhook events
    switch (evt.type) {
      case "user.created":
        await UserHandler.createUser(evt.data);
        break;

      case "user.updated":
        await UserHandler.updateUser(evt.data.id, evt.data);
        break;

      case "user.deleted":
        await UserHandler.deleteUser(evt.data.id);
        break;

      default:
        console.log(`ℹ️ Unhandled webhook event type: ${evt.type}`);
    }

    return res.status(200).json({
      success: true,
      message: "Webhook processed successfully",
      eventType: evt.type,
    });
  } catch (error) {
    console.error("❌ Error processing webhook:", error);
    return res.status(500).json({
      success: false,
      message: "Internal server error processing webhook",
    });
  }
};
