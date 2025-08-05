use crate::proto::user::{GetUserRequest, GetUserResponse, user_service_client::UserServiceClient};
use anyhow::{Result, anyhow};
use tonic::transport::{Channel, Endpoint};
use tracing::{debug, error, info, warn};

#[derive(Debug, Clone)]
pub struct UserClient {
    client: UserServiceClient<Channel>,
}

impl UserClient {
    /// Create a new UserClient with the given service URL
    pub async fn new(service_url: String) -> Result<Self> {
        info!("Connecting to user service at: {}", service_url);

        let endpoint = Endpoint::from_shared(service_url)
            .map_err(|e| anyhow!("Invalid endpoint URL: {}", e))?;

        let channel = endpoint
            .connect()
            .await
            .map_err(|e| anyhow!("Failed to connect to user service: {}", e))?;

        let client = UserServiceClient::new(channel);

        info!("Successfully connected to user service");
        Ok(Self { client })
    }

    /// Create a new UserClient with custom channel configuration
    pub async fn new_with_config(service_url: String, timeout_seconds: u64) -> Result<Self> {
        info!(
            "Connecting to user service at: {} with timeout: {}s",
            service_url, timeout_seconds
        );

        let endpoint = Endpoint::from_shared(service_url)
            .map_err(|e| anyhow!("Invalid endpoint URL: {}", e))?
            .timeout(std::time::Duration::from_secs(timeout_seconds));

        let channel = endpoint
            .connect()
            .await
            .map_err(|e| anyhow!("Failed to connect to user service: {}", e))?;

        let client = UserServiceClient::new(channel);

        info!("Successfully connected to user service with custom config");
        Ok(Self { client })
    }

    /// Get user by ID
    pub async fn get_user(&mut self, user_id: String) -> Result<GetUserResponse> {
        debug!("Fetching user with ID: {}", user_id);

        if user_id.is_empty() {
            return Err(anyhow!("User ID cannot be empty"));
        }

        let request = tonic::Request::new(GetUserRequest {
            user_id: user_id.clone(),
        });

        match self.client.get_user(request).await {
            Ok(response) => {
                let user_response = response.into_inner();

                if user_response.success {
                    info!("Successfully fetched user: {}", user_id);
                    debug!("User response: {:?}", user_response);
                } else {
                    warn!(
                        "Failed to fetch user {}: {}",
                        user_id, user_response.message
                    );
                }

                Ok(user_response)
            }
            Err(status) => {
                error!("gRPC error while fetching user {}: {:?}", user_id, status);
                Err(anyhow!("Failed to get user: {}", status.message()))
            }
        }
    }

    /// Check if user exists (convenience method)
    pub async fn user_exists(&mut self, user_id: String) -> Result<bool> {
        match self.get_user(user_id).await {
            Ok(response) => Ok(response.success && response.user.is_some()),
            Err(_) => Ok(false), // Assume user doesn't exist if there's an error
        }
    }

    /// Get user safely with error handling
    pub async fn get_user_safe(&mut self, user_id: String) -> Option<crate::proto::user::User> {
        match self.get_user(user_id).await {
            Ok(response) if response.success => response.user,
            Ok(response) => {
                warn!("User service returned error: {}", response.message);
                None
            }
            Err(e) => {
                error!("Failed to get user: {}", e);
                None
            }
        }
    }

    /// Health check method to verify connection
    pub async fn health_check(&mut self) -> bool {
        // Try to make a request with a dummy user ID to test connectivity
        match self.get_user("health_check".to_string()).await {
            Ok(_) => true,
            Err(e) => {
                error!("Health check failed: {}", e);
                false
            }
        }
    }
}

// Optional: Implement a connection pool for multiple clients
#[derive(Debug)]
pub struct UserClientPool {
    clients: Vec<UserClient>,
    current_index: std::sync::atomic::AtomicUsize,
}

impl UserClientPool {
    pub async fn new(service_urls: Vec<String>) -> Result<Self> {
        let mut clients = Vec::new();

        for url in service_urls {
            let client = UserClient::new(url).await?;
            clients.push(client);
        }

        if clients.is_empty() {
            return Err(anyhow!("No user service URLs provided"));
        }

        Ok(Self {
            clients,
            current_index: std::sync::atomic::AtomicUsize::new(0),
        })
    }

    pub fn get_client(&mut self) -> &mut UserClient {
        let index = self
            .current_index
            .load(std::sync::atomic::Ordering::Relaxed);
        let next_index = (index + 1) % self.clients.len();
        self.current_index
            .store(next_index, std::sync::atomic::Ordering::Relaxed);
        &mut self.clients[index]
    }
}
