// Switch to the user database
db = db.getSiblingDB("user_db");

// Create application user with read/write permissions
db.createUser({
  user: "mongo",
  pwd: "v3jjS70vmYmB",
  roles: [
    {
      role: "readWrite",
      db: "user_db",
    },
    {
      role: "dbAdmin",
      db: "user_db",
    },
  ],
});

// Create indexes for better performance
db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ clerk_user_id: 1 }, { unique: true });
db.users.createIndex({ username: 1 }, { unique: true, sparse: true });
db.users.createIndex({ created_at: 1 });
db.users.createIndex({ updated_at: 1 });
db.users.createIndex({ is_active: 1 });

print("MongoDB user_db initialization completed successfully!");
print("Created user: user_service");
print("Created indexes for performance optimization");
print("Database is ready for the user service!");
