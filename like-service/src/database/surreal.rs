use anyhow::Result;
use surrealdb::{
    Surreal,
    engine::local::{Db, RocksDb},
};
use tracing::{info, warn};

#[derive(Debug, Clone)]
pub struct Database {
    pub client: Surreal<Db>,
}

impl Database {
    pub async fn new(database_url: &str) -> Result<Self> {
        info!("Connecting to database: {}", database_url);

        let client = if database_url.starts_with("rocksdb://") {
            let path = database_url
                .strip_prefix("rocksdb://")
                .unwrap_or("/data/likes.db");
            info!("Using RocksDB at path: {}", path);
            Surreal::new::<RocksDb>(path).await?
        } else {
            warn!("Fallback to in-memory database");
            Surreal::new::<surrealdb::engine::local::Mem>(()).await?
        };

        // Use namespace and database
        client.use_ns("likes_service").use_db("likes").await?;

        // Initialize schema
        Self::initialize_schema(&client).await?;

        Ok(Database { client })
    }

    async fn initialize_schema(client: &Surreal<Db>) -> Result<()> {
        info!("Initializing database schema");

        // Create likes table with indexes
        let _: surrealdb::Response = client
            .query(
                r#"
                DEFINE TABLE likes SCHEMAFULL;
                DEFINE FIELD id ON TABLE likes TYPE string;
                DEFINE FIELD user_id ON TABLE likes TYPE string ASSERT $value != NONE;
                DEFINE FIELD post_id ON TABLE likes TYPE string ASSERT $value != NONE;
                DEFINE FIELD liked_at ON TABLE likes TYPE datetime DEFAULT time::now();
                DEFINE FIELD created_at ON TABLE likes TYPE datetime DEFAULT time::now();
                DEFINE FIELD updated_at ON TABLE likes TYPE datetime DEFAULT time::now();

                DEFINE INDEX likes_user_post ON TABLE likes COLUMNS user_id, post_id UNIQUE;
                DEFINE INDEX likes_user_id ON TABLE likes COLUMNS user_id;
                DEFINE INDEX likes_post_id ON TABLE likes COLUMNS post_id;
                DEFINE INDEX likes_created_at ON TABLE likes COLUMNS created_at;
                "#,
            )
            .await?;

        info!("Database schema initialized successfully");
        Ok(())
    }

    pub async fn health_check(&self) -> Result<bool, surrealdb::Error> {
        let _: surrealdb::Response = self.client.query("INFO FOR DB").await?;
        Ok(true)
    }
}
