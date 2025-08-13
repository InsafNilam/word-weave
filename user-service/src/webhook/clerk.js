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
    const result = await UserHandler.handleWebhookEvent(evt.type, evt.data);

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
