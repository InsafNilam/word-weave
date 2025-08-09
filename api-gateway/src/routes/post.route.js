import express from "express";
import { postClient } from "../clients/post.client.js";
import { likeClient } from "../clients/like.client.js";
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

router.post("/:id/like", authorizeByRole([]), (req, res) => {
  const { id } = req.params;
  const { user_id } = req.body;

  likeClient.LikePost({ post_id: id, user_id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.delete("/:id/unlike", authorizeByRole([]), (req, res) => {
  const { id } = req.params;
  const { user_id } = req.body;

  likeClient.UnlikePost({ post_id: id, user_id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
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

router.patch("/:id", authorizeByRole([]), (req, res) => {
  const { id } = req.params;
  const postData = req.body;

  // Filter out undefined/null values for true PATCH behavior
  const filteredData = Object.fromEntries(
    Object.entries(postData).filter(
      ([_, value]) => value !== undefined && value !== null
    )
  );

  postClient.PatchPost(
    {
      id: parseInt(id),
      user_id: req.user?.id,
      ...filteredData,
    },
    (err, response) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json(response);
    }
  );
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

router.get("/likes/count", (req, res) => {
  let { ids } = req.query;

  // If id is a string, convert to array; if already array, use as is
  let post_ids = Array.isArray(ids)
    ? ids
    : typeof ids === "string"
    ? [ids]
    : [];

  if (post_ids.length === 0) {
    return res
      .status(400)
      .json({ error: "Missing or invalid 'id' query parameter" });
  }

  likeClient.GetLikesCountBulk({ post_ids }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/:id/likes", (req, res) => {
  const { id } = req.params;
  const { limit, offset } = req.query;

  likeClient.GetPostLikes({ post_id: id, limit, offset }, (err, response) => {
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

router.get("/:id/likes/count", (req, res) => {
  const { id } = req.params;

  likeClient.GetLikesCount({ post_id: id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

export default router;
