import express from "express";
import { likeClient } from "../clients/like.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.get("/health", (req, res) => {
  likeClient.HealthCheck({}, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

export default router;
