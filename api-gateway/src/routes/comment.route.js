import express from "express";
import { commentClient } from "../clients/comment.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.post("/", authorizeByRole([]), (req, res) => {
  const auth = req.auth() || {};
  const user_id = auth?.userId;

  const { post_id, description } = req.body;

  commentClient.CreateComment(
    { post_id, description, user_id },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.status(201).json(response);
    }
  );
});

router.get("/:id", (req, res) => {
  const id = req.params.id;

  commentClient.GetComment({ id }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.get("/posts/:id", (req, res) => {
  const post_id = req.params.id;
  const { limit, offset } = req.query;

  commentClient.GetCommentsByPost(
    { post_id, limit, offset },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.get("/users/:id", (req, res) => {
  const user_id = req.params.id;
  const { limit, offset } = req.query;

  commentClient.GetCommentsByUser(
    { user_id, limit, offset },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.patch("/:id", authorizeByRole([]), (req, res) => {
  const auth = req.auth() || {};
  const user_id = auth?.userId;

  const id = req.params.id;
  const { description } = req.body;

  commentClient.UpdateComment(
    { id, user_id, description },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.status(200).json(response);
    }
  );
});

router.delete("/:id", authorizeByRole([]), (req, res) => {
  const auth = req.auth() || {};
  const user_id = auth?.userId;

  const id = req.params.id;

  commentClient.DeleteComment({ id, user_id }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.status(200).json(response);
  });
});

router.get("/posts/:id/comments", (req, res) => {
  const post_id = req.params.id;

  commentClient.GetCommentCount({ post_id }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.delete("/bulk", authorizeByRole([]), (req, res) => {
  const { post_ids, user_ids } = req.body;

  commentClient.DeleteComments({ post_ids, user_ids }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.status(200).json(response);
  });
});

export default router;
