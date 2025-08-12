use crate::proto::post::{GetPostRequest, GetPostResponse, post_service_client::PostServiceClient};
use anyhow::{Result, anyhow};
use tonic::transport::{Channel, Endpoint};
use tracing::{debug, error, info, warn};

#[derive(Debug, Clone)]
pub struct PostClient {
    client: PostServiceClient<Channel>,
}

impl PostClient {
    /// Create a new PostClient with the given service URL
    pub async fn new(service_url: String) -> Result<Self> {
        info!("Connecting to post service at: {}", service_url);

        let endpoint = Endpoint::from_shared(service_url)
            .map_err(|e| anyhow!("Invalid endpoint URL: {}", e))?;

        let channel = endpoint
            .connect()
            .await
            .map_err(|e| anyhow!("Failed to connect to post service: {}", e))?;

        let client = PostServiceClient::new(channel);

        info!("Successfully connected to post service");
        Ok(Self { client })
    }

    /// Create a new PostClient with custom channel configuration
    pub async fn new_with_config(service_url: String, timeout_seconds: u64) -> Result<Self> {
        info!(
            "Connecting to post service at: {} with timeout: {}s",
            service_url, timeout_seconds
        );

        let endpoint = Endpoint::from_shared(service_url)
            .map_err(|e| anyhow!("Invalid endpoint URL: {}", e))?
            .timeout(std::time::Duration::from_secs(timeout_seconds));

        let channel = endpoint
            .connect()
            .await
            .map_err(|e| anyhow!("Failed to connect to post service: {}", e))?;

        let client = PostServiceClient::new(channel);

        info!("Successfully connected to post service with custom config");
        Ok(Self { client })
    }

    /// Get post by ID
    pub async fn get_post(&mut self, post_id: u32) -> Result<GetPostResponse> {
        debug!("Fetching post with ID: {}", post_id);

        if post_id <= 0 {
            return Err(anyhow!("Post ID must be a positive integer"));
        }

        let request = tonic::Request::new(GetPostRequest { post_id });

        match self.client.get_post(request).await {
            Ok(response) => {
                let post_response = response.into_inner();

                if post_response.success {
                    info!("Successfully fetched post: {}", post_id);
                    debug!("Post response: {:?}", post_response);
                } else {
                    warn!(
                        "Failed to fetch post {}: {}",
                        post_id, post_response.message
                    );
                }

                Ok(post_response)
            }
            Err(status) => {
                error!("gRPC error while fetching post {}: {:?}", post_id, status);
                Err(anyhow!("Failed to get post: {}", status.message()))
            }
        }
    }

    /// Check if post exists (convenience method)
    pub async fn post_exists(&mut self, post_id: u32) -> Result<bool> {
        match self.get_post(post_id).await {
            Ok(response) => Ok(response.success),
            Err(_) => Ok(false),
        }
    }

    /// Get post safely with error handling
    pub async fn get_post_safe(&mut self, post_id: u32) -> Option<crate::proto::post::Post> {
        match self.get_post(post_id).await {
            Ok(response) if response.success => response.post,
            Ok(response) => {
                warn!("Post service returned error: {}", response.message);
                None
            }
            Err(e) => {
                error!("Failed to get post: {}", e);
                None
            }
        }
    }

    /// Get post author ID (convenience method)
    pub async fn get_post_author(&mut self, post_id: u32) -> Option<String> {
        match self.get_post_safe(post_id).await {
            Some(post) => Some(post.user_id),
            None => None,
        }
    }

    /// Validate post ownership
    pub async fn is_post_owner(&mut self, post_id: u32, user_id: &str) -> Result<bool> {
        match self.get_post_author(post_id).await {
            Some(author_id) => Ok(author_id == user_id),
            None => Ok(false),
        }
    }

    /// Health check method to verify connection
    pub async fn health_check(&mut self) -> bool {
        // Try to make a request with a dummy post ID to test connectivity
        match self.get_post(1).await {
            Ok(_) => true,
            Err(e) => {
                error!("Health check failed: {}", e);
                false
            }
        }
    }

    /// Batch get posts (if you need to fetch multiple posts)
    pub async fn get_posts_batch(
        &mut self,
        post_ids: Vec<u32>,
    ) -> Vec<Option<crate::proto::post::Post>> {
        let mut results = Vec::new();

        for post_id in post_ids {
            let post = self.get_post_safe(post_id).await;
            results.push(post);
        }

        results
    }
}

#[derive(Debug)]
pub struct PostClientPool {
    clients: Vec<PostClient>,
    current_index: std::sync::atomic::AtomicUsize,
}

impl PostClientPool {
    pub async fn new(service_urls: Vec<String>) -> Result<Self> {
        let mut clients = Vec::new();

        for url in service_urls {
            let client = PostClient::new(url).await?;
            clients.push(client);
        }

        if clients.is_empty() {
            return Err(anyhow!("No post service URLs provided"));
        }

        Ok(Self {
            clients,
            current_index: std::sync::atomic::AtomicUsize::new(0),
        })
    }

    pub fn get_client(&mut self) -> &mut PostClient {
        let index = self
            .current_index
            .load(std::sync::atomic::Ordering::Relaxed);
        let next_index = (index + 1) % self.clients.len();
        self.current_index
            .store(next_index, std::sync::atomic::Ordering::Relaxed);
        &mut self.clients[index]
    }
}

// Utility functions for working with posts
impl PostClient {
    /// Extract post metadata without full content (useful for listings)
    pub async fn get_post_metadata(&mut self, post_id: u32) -> Option<PostMetadata> {
        match self.get_post_safe(post_id).await {
            Some(post) => Some(PostMetadata {
                id: post.id,
                title: post.title,
                author_id: post.user_id,
                content_preview: if post.content.len() > 100 {
                    format!("{}...", &post.content[..100])
                } else {
                    post.content
                },
            }),
            None => None,
        }
    }
}

/// Lightweight post metadata structure
#[derive(Debug, Clone)]
pub struct PostMetadata {
    pub id: u32,
    pub title: String,
    pub author_id: String,
    pub content_preview: String,
}
