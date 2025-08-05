mod clients;
mod config;
mod database;
mod error;
mod models;
mod repository;
mod service;

use anyhow::Result;
use std::net::SocketAddr;
use tokio::signal;
use tonic::transport::Server;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::{
    clients::{PostClient, UserClient},
    config::Config,
    database::Database,
    repository::LikesRepository,
    service::LikesServiceImpl,
};

// Include the generated gRPC code
pub mod proto {
    tonic::include_proto!("like");
    pub mod user {
        tonic::include_proto!("user");
    }
    pub mod post {
        tonic::include_proto!("post");
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "likes_service=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Config::from_env()?;
    info!("Starting likes service on {}:{}", config.host, config.port);

    // Initialize database
    let database = Database::new(&config.database_url).await?;
    info!("Connected to SurrealDB");

    // Initialize user client
    let user_client = UserClient::new(config.user_service_url).await?;
    info!("Connected to User Service");

    // Initialize post client
    let post_client = PostClient::new(config.post_service_url).await?;
    info!("Connected to Post Service");

    // Initialize repository
    let repository = LikesRepository::new(database);

    // Initialize service
    let likes_service = LikesServiceImpl::new(repository, user_client, post_client);

    // Build server address
    let addr: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;

    // Start gRPC server
    info!("gRPC server listening on {}", addr);

    Server::builder()
        .add_service(proto::likes_service_server::LikesServiceServer::new(
            likes_service,
        ))
        .serve_with_shutdown(addr, async {
            signal::ctrl_c()
                .await
                .expect("Failed to install Ctrl+C handler");
            println!("Shutting down...");
        })
        .await?;

    Ok(())
}
