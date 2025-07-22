import express from "express";
import { userClient } from "../clients/user.client.js";
import { likeClient } from "../clients/like.client.js";
import { authorizeByRole } from "../middleware/auth.js";

const router = express.Router();

router.get("/", authorizeByRole(["admin"]), (req, res) => {
  const { limit, offset } = req.query;

  userClient.ListUsers({ limit, offset }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/search", authorizeByRole(["admin"]), (req, res) => {
  const { limit, offset } = req.query;
  const { email_address, username, user_id } = req.body;

  userClient.SearchUsers(
    { email_address, username, user_id, limit, offset },
    (err, response) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json(response);
    }
  );
});

router.get("/count", authorizeByRole(["admin"]), (req, res) => {
  const { email_address, username, user_id } = req.body;

  userClient.CountUsers(
    { email_address, username, user_id },
    (err, response) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json(response);
    }
  );
});

router.get("/token", authorizeByRole(["admin"]), (req, res) => {
  const { user_id } = req.query;

  userClient.GetOAuthAccessToken(
    { user_id, provider: "google" },
    (err, response) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json(response);
    }
  );
});

router.get("/:id", authorizeByRole(["admin"]), (req, res) => {
  const user_id = req.params.id;

  userClient.GetUser({ user_id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/:id/likes", (req, res) => {
  const { id } = req.params;
  const { limit, offset } = req.query;

  likeClient.GetUserLikes({ user_id: id, limit, offset }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.get("/:user/posts/:post", (req, res) => {
  const { user, post } = req.params;

  postClient.IsPostLiked({ user_id: user, post_id: post }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.post("/", authorizeByRole(["admin"]), (req, res) => {
  const userData = req.body;
  userClient.CreateUser(userData, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(201).json(response);
  });
});

router.put("/:id", authorizeByRole(["admin"]), (req, res) => {
  const user_id = req.params.id;
  const userData = req.body;

  userClient.UpdateUser({ user_id, ...userData }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.delete("/:id", authorizeByRole(["admin"]), (req, res) => {
  const user_id = req.params.id;

  userClient.DeleteUser({ user_id }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

router.put("/:id/role", authorizeByRole(["admin"]), (req, res) => {
  const user_id = req.params.id;
  const { role } = req.body;
  userClient.UpdateUserRole({ user_id, role }, (err, response) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(response);
  });
});

export default router;
