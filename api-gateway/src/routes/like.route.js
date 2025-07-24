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

router.post("/", authorizeByRole([]), (req, res) => {
  const { user_id, post_id } = req.body;

  likeClient.LikePost({ user_id, post_id }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.status(201).json(response);
  });
});

router.delete("/", authorizeByRole([]), (req, res) => {
  const { user_id, post_id } = req.body;

  likeClient.UnlikePost({ user_id, post_id }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.status(200).json(response);
  });
});

router.delete("/posts/unlike", authorizeByRole([]), (req, res) => {
  const { post_ids, user_ids } = req.body;

  likeClient.UnlikePosts({ post_ids, user_ids }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.status(200).json(response);
  });
});

router.get("/users/:id", (req, res) => {
  const userId = req.params.id;
  const { limit, offset } = req.query;

  likeClient.GetUserLikes(
    { user_id: userId, limit, offset },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.get("/posts/:id", (req, res) => {
  const postId = req.params.id;
  const { limit, offset } = req.query;

  likeClient.GetPostLikes(
    { post_id: postId, limit, offset },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

router.get("/posts/:id/likes", (req, res) => {
  const postId = req.params.id;

  likeClient.GetLikesCount({ post_id: postId }, (error, response) => {
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    res.json(response);
  });
});

router.get("/users/:user/posts/:post", (req, res) => {
  const userId = req.params.user;
  const postId = req.params.post;

  likeClient.IsPostLiked(
    { post_id: postId, user_id: userId },
    (error, response) => {
      if (error) {
        return res.status(500).json({ error: error.message });
      }
      res.json(response);
    }
  );
});

export default router;
