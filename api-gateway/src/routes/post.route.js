import express from "express";
import { postClient } from "../clients/post.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.get("/", (req, res) => {
  const { limit, offset } = req.query;

  postClient.ListPosts({ limit, offset }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/:id", (req, res) => {
  const { id } = req.params;

  postClient.GetPost({ id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.post("/", authorizeByRole([]), (req, res) => {
  const postData = req.body;

  postClient.CreatePost(postData, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(201).json(response);
  });
});

router.put("/:id", authorizeByRole([]), (req, res) => {
  const { id } = req.params;
  const postData = req.body;

  postClient.UpdatePost({ id, ...postData }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.delete("/:id", authorizeByRole([]), (req, res) => {
  const { id } = req.params;
  const { user_id } = req.body;

  postClient.DeletePost({ id, user_id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(204).send();
  });
});

router.get("/search", (req, res) => {
  const { query } = req.query;

  postClient.SearchPosts({ query }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/featured", (req, res) => {
  const { limit } = req.query;
  postClient.GetFeaturedPosts({ limit }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/count", authorizeByRole(["admin"]), (req, res) => {
  const { user_id, category, is_featured } = req.query;

  postClient.CountPosts({ user_id, category, is_featured }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/slug/:slug", (req, res) => {
  const { slug } = req.params;

  postClient.GetPostBySlug({ slug }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/user/:id", (req, res) => {
  const { id } = req.params;

  postClient.GetPostsByUser({ user_id: id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/category/:category", (req, res) => {
  const { category } = req.params;

  postClient.GetPostsByCategory({ category }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

export default router;
