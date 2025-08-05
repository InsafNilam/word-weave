use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub environment: String,
    pub log_level: String,
    pub user_service_url: String,
    pub post_service_url: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Config {
            host: env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "50053".to_string())
                .parse()?,
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "rocksdb://./data/likes.db".to_string()),
            environment: env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
            log_level: env::var("LOG_LEVEL").unwrap_or_else(|_| "debug".to_string()),
            user_service_url: env::var("USER_SERVICE_URL")
                .unwrap_or_else(|_| "http://localhost:50051".to_string()),
            post_service_url: env::var("POST_SERVICE_URL")
                .unwrap_or_else(|_| "http://localhost:50052".to_string()),
        })
    }
}
