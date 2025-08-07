db.createUser({
  user: "mongo",
  pwd: "v3jjS70vmYmB",
  roles: [
    {
      role: "readWrite",
      db: "user_db",
    },
  ],
});
