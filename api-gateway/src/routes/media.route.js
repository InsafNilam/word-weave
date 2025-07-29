import express from "express";
import { mediaClient } from "../clients/media.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.get("/auth", authorizeByRole([]), (req, res) => {
  mediaClient.GetUploadAuth({}, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.post("/upload", authorizeByRole([]), (req, res) => {
  mediaClient.UploadFile(req.body, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.get("/files", authorizeByRole(["admin"]), (req, res) => {
  const { limit, offset } = req.query;
  mediaClient.GetFiles({ limit, offset }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.get("/files/:id", authorizeByRole(["admin"]), (req, res) => {
  const fileId = req.params.id;

  mediaClient.GetFileById({ id: fileId }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.delete("/files", authorizeByRole(["admin"]), (req, res) => {
  const { ids } = req.body;
  mediaClient.DeleteMultipleFiles({ file_ids: ids }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.delete("/files/:id", authorizeByRole(["admin"]), (req, res) => {
  const fileId = req.params.id;

  mediaClient.DeleteFile({ id: fileId }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.patch("/files/:id", authorizeByRole(["admin"]), (req, res) => {
  const { tags, custom_coordinates, custom_metadata } = req.body;
  mediaClient.UpdateFileDetails(
    {
      file_id: req.params.id,
      tags,
      custom_coordinates,
      custom_metadata,
    },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

export default router;
