use anyhow::Result;
use surrealdb::{
    Surreal,
    engine::{
        local::{Db, Mem, RocksDb},
        remote::ws::{Client, Ws},
    },
    opt::auth::Root,
};
use tracing::{error, info, warn};

#[derive(Debug, Clone)]
pub enum DatabaseClient {
    Local(Surreal<Db>),
    Remote(Surreal<Client>),
}

#[derive(Debug, Clone)]
pub struct Database {
    pub client: DatabaseClient,
}

impl Database {
    pub async fn new(database_url: &str) -> Result<Self> {
        info!("Connecting to database: {}", database_url);

        let client = if database_url.starts_with("ws://") || database_url.starts_with("wss://") {
            // Remote SurrealDB connection (Docker)
            info!("Connecting to remote SurrealDB instance: {}", database_url);

            let surreal_client = Surreal::new::<Ws>(database_url)
                .await
                .map_err(|e| anyhow::anyhow!("Failed to connect to SurrealDB: {}", e))?;

            // Get credentials from environment
            let user = std::env::var("DB_USER").map_err(|_| {
                anyhow::anyhow!(
                    "SURREAL_DB_USER environment variable is required for remote connections"
                )
            })?;
            let password = std::env::var("DB_PASSWORD").map_err(|_| {
                anyhow::anyhow!(
                    "SURREAL_DB_PASSWORD environment variable is required for remote connections"
                )
            })?;

            // Sign in with root credentials
            surreal_client
                .signin(Root {
                    username: &user,
                    password: &password,
                })
                .await
                .map_err(|e| anyhow::anyhow!("Failed to authenticate with SurrealDB: {}", e))?;

            info!("Successfully authenticated with SurrealDB");

            // Use namespace and database
            surreal_client
                .use_ns("likes_service")
                .use_db("likes")
                .await
                .map_err(|e| anyhow::anyhow!("Failed to select namespace/database: {}", e))?;

            DatabaseClient::Remote(surreal_client)
        } else if database_url.starts_with("rocksdb://") {
            // Local RocksDB
            let path = database_url
                .strip_prefix("rocksdb://")
                .unwrap_or("/data/likes.db");
            info!("Using RocksDB at path: {}", path);

            let surreal_client = Surreal::new::<RocksDb>(path)
                .await
                .map_err(|e| anyhow::anyhow!("Failed to initialize RocksDB: {}", e))?;

            // Use namespace and database
            surreal_client
                .use_ns("likes_service")
                .use_db("likes")
                .await
                .map_err(|e| anyhow::anyhow!("Failed to select namespace/database: {}", e))?;

            DatabaseClient::Local(surreal_client)
        } else {
            // Fallback to in-memory database
            warn!("Using in-memory database (data will be lost on restart)");

            let surreal_client = Surreal::new::<Mem>(())
                .await
                .map_err(|e| anyhow::anyhow!("Failed to initialize in-memory database: {}", e))?;

            // Use namespace and database
            surreal_client
                .use_ns("likes_service")
                .use_db("likes")
                .await
                .map_err(|e| anyhow::anyhow!("Failed to select namespace/database: {}", e))?;

            DatabaseClient::Local(surreal_client)
        };

        let database = Database { client };

        // Initialize schema
        database.initialize_schema().await?;

        Ok(database)
    }

    async fn initialize_schema(&self) -> Result<()> {
        info!("Initializing database schema");

        let schema_query = r#"
            -- Remove table if exists and recreate (for development)
            -- REMOVE TABLE IF EXISTS likes;
            
            -- Define the likes table with schema
            DEFINE TABLE likes SCHEMAFULL;
            
            -- Define fields with proper types and constraints
            DEFINE FIELD user_id ON TABLE likes TYPE string 
                ASSERT $value != NONE AND string::len($value) > 0;
            DEFINE FIELD post_id ON TABLE likes TYPE string 
                ASSERT $value != NONE AND string::len($value) > 0;
            DEFINE FIELD liked_at ON TABLE likes TYPE datetime DEFAULT time::now();
            DEFINE FIELD created_at ON TABLE likes TYPE datetime DEFAULT time::now();
            DEFINE FIELD updated_at ON TABLE likes TYPE datetime DEFAULT time::now() 
                VALUE $before OR time::now();

            -- Define indexes for performance
            DEFINE INDEX likes_user_post ON TABLE likes COLUMNS user_id, post_id UNIQUE;
            DEFINE INDEX likes_user_id ON TABLE likes COLUMNS user_id;
            DEFINE INDEX likes_post_id ON TABLE likes COLUMNS post_id;
            DEFINE INDEX likes_created_at ON TABLE likes COLUMNS created_at;
            DEFINE INDEX likes_liked_at ON TABLE likes COLUMNS liked_at;
        "#;

        let result = match &self.client {
            DatabaseClient::Local(client) => client.query(schema_query).await,
            DatabaseClient::Remote(client) => client.query(schema_query).await,
        };

        match result {
            Ok(_) => {
                info!("Database schema initialized successfully");
                Ok(())
            }
            Err(e) => {
                error!("Failed to initialize database schema: {}", e);
                Err(anyhow::anyhow!("Schema initialization failed: {}", e))
            }
        }
    }

    pub async fn health_check(&self) -> Result<bool, surrealdb::Error> {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.query("INFO FOR DB").await,
            DatabaseClient::Remote(client) => client.query("INFO FOR DB").await,
        };

        match result {
            Ok(_) => {
                info!("Database health check passed");
                Ok(true)
            }
            Err(e) => {
                error!("Database health check failed: {}", e);
                Err(e)
            }
        }
    }

    // Helper method to execute queries
    pub async fn query(&self, sql: &str) -> Result<surrealdb::Response> {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.query(sql).await,
            DatabaseClient::Remote(client) => client.query(sql).await,
        };

        result.map_err(|e| anyhow::anyhow!("Query failed: {}", e))
    }

    // Helper method to create records
    pub async fn create<T>(&self, resource: &str) -> Result<Vec<T>>
    where
        T: serde::de::DeserializeOwned,
    {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.create(resource).await,
            DatabaseClient::Remote(client) => client.create(resource).await,
        };

        result
            .map(|opt| opt.map_or_else(Vec::new, |v| vec![v]))
            .map_err(|e| anyhow::anyhow!("Create failed: {}", e))
    }

    // Helper method to select records
    pub async fn select<T>(&self, resource: &str) -> Result<Vec<T>>
    where
        T: serde::de::DeserializeOwned,
    {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.select(resource).await,
            DatabaseClient::Remote(client) => client.select(resource).await,
        };

        result.map_err(|e| anyhow::anyhow!("Select failed: {}", e))
    }

    // Helper method to update records
    pub async fn update<T, U>(&self, resource: &str, data: T) -> Result<Vec<U>>
    where
        T: serde::Serialize + 'static,
        U: serde::de::DeserializeOwned,
    {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.update(resource).content(data).await,
            DatabaseClient::Remote(client) => client.update(resource).content(data).await,
        };

        result.map_err(|e| anyhow::anyhow!("Update failed: {}", e))
    }

    // Helper method to delete records
    pub async fn delete<T>(&self, resource: &str) -> Result<Vec<T>>
    where
        T: serde::de::DeserializeOwned,
    {
        let result = match &self.client {
            DatabaseClient::Local(client) => client.delete(resource).await,
            DatabaseClient::Remote(client) => client.delete(resource).await,
        };

        result.map_err(|e| anyhow::anyhow!("Delete failed: {}", e))
    }

    // Query builder method for complex queries with bindings
    pub fn query_builder(&self, sql: &str) -> QueryBuilder {
        QueryBuilder {
            sql: sql.to_string(),
            database: self,
            bindings: Vec::new(),
        }
    }

    // Direct query execution with parameters
    pub async fn execute_query_with_params<P>(
        &self,
        sql: &str,
        params: P,
    ) -> Result<surrealdb::Response>
    where
        P: serde::Serialize + 'static,
    {
        match &self.client {
            DatabaseClient::Local(client) => client
                .query(sql)
                .bind(params)
                .await
                .map_err(|e| anyhow::anyhow!("Query with params failed: {}", e)),
            DatabaseClient::Remote(client) => client
                .query(sql)
                .bind(params)
                .await
                .map_err(|e| anyhow::anyhow!("Query with params failed: {}", e)),
        }
    }
}

pub struct QueryBuilder<'a> {
    sql: String,
    database: &'a Database,
    bindings: Vec<(String, serde_json::Value)>,
}

impl<'a> QueryBuilder<'a> {
    pub fn bind<T: serde::Serialize>(mut self, key: &str, value: T) -> Self {
        let json_value = serde_json::to_value(value).unwrap_or(serde_json::Value::Null);
        self.bindings.push((key.to_string(), json_value));
        self
    }

    // Alternative method that returns anyhow::Error for compatibility with existing code
    pub async fn execute_with_anyhow(self) -> Result<surrealdb::Response, anyhow::Error> {
        match &self.database.client {
            DatabaseClient::Local(client) => {
                let mut query_builder = client.query(&self.sql);
                for (key, value) in self.bindings {
                    query_builder = query_builder.bind((key, value));
                }
                query_builder
                    .await
                    .map_err(|e| anyhow::anyhow!("Query execution failed: {}", e))
            }
            DatabaseClient::Remote(client) => {
                let mut query_builder = client.query(&self.sql);
                for (key, value) in self.bindings {
                    query_builder = query_builder.bind((key, value));
                }
                query_builder
                    .await
                    .map_err(|e| anyhow::anyhow!("Query execution failed: {}", e))
            }
        }
    }

    // Return the original SurrealDB error
    pub async fn execute(self) -> Result<surrealdb::Response, surrealdb::Error> {
        match &self.database.client {
            DatabaseClient::Local(client) => {
                let mut query_builder = client.query(&self.sql);
                for (key, value) in self.bindings {
                    query_builder = query_builder.bind((key, value));
                }
                query_builder.await
            }
            DatabaseClient::Remote(client) => {
                let mut query_builder = client.query(&self.sql);
                for (key, value) in self.bindings {
                    query_builder = query_builder.bind((key, value));
                }
                query_builder.await
            }
        }
    }
}
