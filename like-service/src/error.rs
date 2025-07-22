use thiserror::Error;
use tonic::Status;

#[derive(Error, Debug)]
pub enum LikesError {
    #[error("Database error: {0}")]
    Database(#[from] surrealdb::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Already exists: {0}")]
    AlreadyExists(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl From<LikesError> for Status {
    fn from(error: LikesError) -> Self {
        match error {
            LikesError::InvalidInput(msg) => Status::invalid_argument(msg),
            LikesError::NotFound(msg) => Status::not_found(msg),
            LikesError::AlreadyExists(msg) => Status::already_exists(msg),
            LikesError::Database(err) => {
                tracing::error!("Database error: {}", err);
                Status::internal("Database error occurred")
            }
            LikesError::Serialization(err) => {
                tracing::error!("Serialization error: {}", err);
                Status::internal("Serialization error occurred")
            }
            LikesError::Internal(msg) => {
                tracing::error!("Internal error: {}", msg);
                Status::internal(msg)
            }
        }
    }
}

pub type Result<T> = std::result::Result<T, LikesError>;
