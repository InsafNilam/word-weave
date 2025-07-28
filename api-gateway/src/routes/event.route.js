import express from "express";
import { eventClient } from "../clients/event.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.post("/", authorizeByRole([]), (req, res) => {
  const {
    aggregate_id,
    aggregate_type,
    event_type,
    event_data,
    metadata,
    correlation_id,
    causation_id,
  } = req.body;

  eventClient.PublishEvent(
    {
      aggregate_id,
      aggregate_type,
      event_type,
      event_data,
      metadata,
      correlation_id,
      causation_id,
    },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.status(201).json(response);
    }
  );
});

router.get("/", (req, res) => {
  const { limit, offset } = req.query;
  const { aggregate_type, event_type } = req.body;

  eventClient.GetEvents(
    { aggregate_type, event_type, limit, offset },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.get("/aggregate", (req, res) => {
  const { aggregate_id, aggregate_type, from_version } = req.query;
  // Add your logic here, for example:
  eventClient.GetEventsByAggregate(
    { aggregate_id, aggregate_type, from_version },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.post("/subscribe", (req, res) => {
  const { consumer_group, event_types, callback_url } = req.body;

  eventClient.SubscribeToEvents(
    { consumer_group, event_types, callback_url },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.status(201).json(response);
    }
  );
});

export default router;
