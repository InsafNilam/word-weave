use crate::{
    database::Database,
    error::{LikesError, Result},
    models::{Like, PaginatedResult, PaginationParams},
};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use tracing::{debug, error};

#[derive(Debug, Clone)]
pub struct LikesRepository {
    db: Database,
}

impl LikesRepository {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub async fn create_like(&self, user_id: &str, post_id: &str) -> Result<Like> {
        debug!("Creating like for user {} on post {}", user_id, post_id);

        // Validate input
        if user_id.is_empty() || post_id.is_empty() {
            return Err(LikesError::InvalidInput(
                "User ID and Post ID cannot be empty".to_string(),
            ));
        }

        let like = Like::new(user_id.to_string(), post_id.to_string());

        let query = r#"
            CREATE likes SET 
                id = $id,
                user_id = $user_id,
                post_id = $post_id,
                liked_at = $liked_at,
                created_at = $created_at,
                updated_at = $updated_at;
        "#;

        let mut result = self
            .db
            .client
            .query(query)
            .bind(("id", like.id.clone()))
            .bind(("user_id", like.user_id.clone()))
            .bind(("post_id", like.post_id.clone()))
            .bind(("liked_at", like.liked_at))
            .bind(("created_at", like.created_at))
            .bind(("updated_at", like.updated_at))
            .await
            .map_err(|e| {
                error!("Failed to create like: {}", e);
                if e.to_string().contains("duplicate") {
                    LikesError::AlreadyExists("User has already liked this post".to_string())
                } else {
                    LikesError::Database(e)
                }
            })?;

        let created_like: Option<Like> = result.take(0)?;
        created_like.ok_or_else(|| LikesError::Internal("Failed to create like".to_string()))
    }

    pub async fn delete_like(&self, user_id: &str, post_id: &str) -> Result<bool> {
        debug!("Deleting like for user {} on post {}", user_id, post_id);

        let query = r#"
            DELETE likes WHERE user_id = $user_id AND post_id = $post_id;
        "#;

        let mut result = self
            .db
            .client
            .query(query)
            .bind(("user_id", user_id.to_string()))
            .bind(("post_id", post_id.to_string()))
            .await
            .map_err(LikesError::Database)?;

        let deleted: Vec<Like> = result.take(0)?;
        Ok(!deleted.is_empty())
    }

    pub async fn get_user_likes(
        &self,
        user_id: &str,
        params: &PaginationParams,
    ) -> Result<PaginatedResult<Like>> {
        debug!(
            "Getting likes for user {} (page: {}, limit: {})",
            user_id, params.page, params.limit
        );

        // Get total count
        let count_query = "SELECT count() FROM likes WHERE user_id = $user_id GROUP ALL;";
        let mut count_result = self
            .db
            .client
            .query(count_query)
            .bind(("user_id", user_id.to_string()))
            .await
            .map_err(LikesError::Database)?;

        let count_data: Option<serde_json::Value> = count_result.take(0)?;
        let total_count = count_data.and_then(|v| v["count"].as_i64()).unwrap_or(0);

        // Get paginated data
        let data_query = r#"
            SELECT * FROM likes 
            WHERE user_id = $user_id 
            ORDER BY created_at DESC 
            LIMIT $limit 
            START $offset;
        "#;

        let mut data_result = self
            .db
            .client
            .query(data_query)
            .bind(("user_id", user_id.to_string()))
            .bind(("limit", params.limit))
            .bind(("offset", params.offset()))
            .await
            .map_err(LikesError::Database)?;

        let likes: Vec<Like> = data_result.take(0)?;

        Ok(PaginatedResult::new(likes, total_count, params))
    }

    pub async fn get_post_likes(
        &self,
        post_id: &str,
        params: &PaginationParams,
    ) -> Result<PaginatedResult<Like>> {
        debug!(
            "Getting likes for post {} (page: {}, limit: {})",
            post_id, params.page, params.limit
        );

        // Get total count
        let count_query = "SELECT count() FROM likes WHERE post_id = $post_id GROUP ALL;";
        let mut count_result = self
            .db
            .client
            .query(count_query)
            .bind(("post_id", post_id.to_string()))
            .await
            .map_err(LikesError::Database)?;

        let count_data: Option<serde_json::Value> = count_result.take(0)?;
        let total_count = count_data.and_then(|v| v["count"].as_i64()).unwrap_or(0);

        // Get paginated data
        let data_query = r#"
            SELECT * FROM likes 
            WHERE post_id = $post_id 
            ORDER BY created_at DESC 
            LIMIT $limit 
            START $offset;
        "#;

        let mut data_result = self
            .db
            .client
            .query(data_query)
            .bind(("post_id", post_id.to_string()))
            .bind(("limit", params.limit))
            .bind(("offset", params.offset()))
            .await
            .map_err(LikesError::Database)?;

        let likes: Vec<Like> = data_result.take(0)?;

        Ok(PaginatedResult::new(likes, total_count, params))
    }

    pub async fn is_post_liked(
        &self,
        user_id: &str,
        post_id: &str,
    ) -> Result<Option<DateTime<Utc>>> {
        debug!("Checking if user {} likes post {}", user_id, post_id);

        let query = r#"
            SELECT liked_at FROM likes 
            WHERE user_id = $user_id AND post_id = $post_id 
            LIMIT 1;
        "#;

        let mut result = self
            .db
            .client
            .query(query)
            .bind(("user_id", user_id.to_string()))
            .bind(("post_id", post_id.to_string()))
            .await
            .map_err(LikesError::Database)?;

        let like: Option<Like> = result.take(0)?;
        Ok(like.map(|l| l.liked_at))
    }

    pub async fn get_likes_count(&self, post_id: &str) -> Result<i64> {
        debug!("Getting likes count for post {}", post_id);

        let query = "SELECT count() FROM likes WHERE post_id = $post_id GROUP ALL;";
        let mut result = self
            .db
            .client
            .query(query)
            .bind(("post_id", post_id.to_string()))
            .await
            .map_err(LikesError::Database)?;

        let count_data: Option<serde_json::Value> = result.take(0)?;
        Ok(count_data.and_then(|v| v["count"].as_i64()).unwrap_or(0))
    }

    pub async fn get_likes_count_bulk(&self, post_ids: &[String]) -> Result<HashMap<String, i64>> {
        debug!("Getting bulk likes count for {} posts", post_ids.len());

        if post_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let query = r#"
            SELECT post_id, count() AS count 
            FROM likes 
            WHERE post_id IN $post_ids 
            GROUP BY post_id;
        "#;

        let post_ids_owned: Vec<String> = post_ids.to_vec();

        let mut result = self
            .db
            .client
            .query(query)
            .bind(("post_ids", post_ids_owned))
            .await
            .map_err(LikesError::Database)?;

        let counts: Vec<serde_json::Value> = result.take(0)?;

        let mut result_map = HashMap::new();

        // Initialize all post IDs with 0 count
        for post_id in post_ids {
            result_map.insert(post_id.clone(), 0i64);
        }

        // Update with actual counts
        for count_data in counts {
            if let (Some(post_id), Some(count)) =
                (count_data["post_id"].as_str(), count_data["count"].as_i64())
            {
                result_map.insert(post_id.to_string(), count);
            }
        }

        Ok(result_map)
    }

    pub async fn health_check(&self) -> Result<bool> {
        self.db.health_check().await.map_err(LikesError::Database)
    }
}
