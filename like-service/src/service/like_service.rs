use crate::{
    clients::{PostClient, UserClient},
    models::PaginationParams,
    proto::{likes_service_server::LikesService, *},
    repository::LikesRepository,
};
use tonic::{Request, Response, Status};
use tracing::{debug, error, info};

#[derive(Debug)]
pub struct LikesServiceImpl {
    repository: LikesRepository,
    user_client: UserClient,
    post_client: PostClient,
}

impl LikesServiceImpl {
    pub fn new(
        repository: LikesRepository,
        user_client: UserClient,
        post_client: PostClient,
    ) -> Self {
        Self {
            repository,
            user_client,
            post_client,
        }
    }

    fn validate_ids(user_id: &str, post_id: &u32) -> Result<(), Status> {
        if user_id.trim().is_empty() {
            return Err(Status::invalid_argument("User ID cannot be empty"));
        }

        if *post_id == 0 {
            return Err(Status::invalid_argument("Post ID must be greater than 0"));
        }

        Ok(())
    }

    async fn validate_user(&mut self, user_id: &str) -> Result<bool, Status> {
        match self.user_client.user_exists(user_id.to_string()).await {
            Ok(exists) => Ok(exists),
            Err(e) => {
                error!("Failed to validate user {}: {}", user_id, e);
                Err(Status::internal("Failed to validate user"))
            }
        }
    }

    // Helper method to validate if post exists
    async fn validate_post(&mut self, post_id: u32) -> Result<bool, Status> {
        match self.post_client.post_exists(post_id).await {
            Ok(exists) => Ok(exists),
            Err(e) => {
                error!("Failed to validate post {}: {}", post_id, e);
                Err(Status::internal("Failed to validate post"))
            }
        }
    }

    fn datetime_to_timestamp(dt: chrono::DateTime<chrono::Utc>) -> prost_types::Timestamp {
        prost_types::Timestamp {
            seconds: dt.timestamp(),
            nanos: dt.timestamp_subsec_nanos() as i32,
        }
    }
}

#[tonic::async_trait]
impl LikesService for LikesServiceImpl {
    async fn like_post(
        &self,
        request: Request<LikePostRequest>,
    ) -> Result<Response<LikePostResponse>, Status> {
        let req = request.into_inner();
        info!(
            "Like post request: user_id={}, post_id={}",
            req.user_id, req.post_id
        );

        Self::validate_ids(&req.user_id, &req.post_id)?;

        // Clone the clients to make them mutable for this call
        let mut user_client = self.user_client.clone();
        let mut post_client = self.post_client.clone();

        // Validate user exists before allowing them to like a post
        if !user_client
            .user_exists(req.user_id.clone())
            .await
            .map_err(|e| Status::internal(format!("User validation failed: {}", e)))?
        {
            return Ok(Response::new(LikePostResponse {
                success: false,
                message: "User not found".to_string(),
                liked_at: None,
            }));
        }

        let user = user_client
            .get_user(req.user_id.clone())
            .await
            .map_err(|e| Status::internal(format!("Failed to get user details: {}", e)))?;

        let db_user_id = user
            .user
            .as_ref()
            .ok_or_else(|| Status::not_found("User not found"))?
            .id
            .clone();

        // Validate post exists before allowing it to be liked
        if !post_client
            .post_exists(req.post_id)
            .await
            .map_err(|e| Status::internal(format!("Post validation failed: {}", e)))?
        {
            return Ok(Response::new(LikePostResponse {
                success: false,
                message: "Post not found".to_string(),
                liked_at: None,
            }));
        }

        match self.repository.create_like(&db_user_id, &req.post_id).await {
            Ok(like) => {
                info!(
                    "Successfully liked post: user_id={}, post_id={}",
                    req.user_id, req.post_id
                );
                Ok(Response::new(LikePostResponse {
                    success: true,
                    message: "Post liked successfully".to_string(),
                    liked_at: Some(Self::datetime_to_timestamp(like.liked_at)),
                }))
            }
            Err(e) => {
                error!("Failed to like post: {}", e);
                println!("Failed to like post: {}", e);
                Err(e.into())
            }
        }
    }

    async fn unlike_post(
        &self,
        request: Request<UnlikePostRequest>,
    ) -> Result<Response<UnlikePostResponse>, Status> {
        let req = request.into_inner();
        info!(
            "Unlike post request: user_id={}, post_id={}",
            req.user_id, req.post_id
        );

        let mut user_client = self.user_client.clone();

        Self::validate_ids(&req.user_id, &req.post_id)?;

        let user = user_client
            .get_user(req.user_id.clone())
            .await
            .map_err(|e| Status::internal(format!("Failed to get user details: {}", e)))?;

        let db_user_id = user
            .user
            .as_ref()
            .ok_or_else(|| Status::not_found("User not found"))?
            .id
            .clone();

        match self.repository.delete_like(&db_user_id, &req.post_id).await {
            Ok(deleted) => {
                if deleted {
                    info!(
                        "Successfully unliked post: user_id={}, post_id={}",
                        req.user_id, req.post_id
                    );
                    Ok(Response::new(UnlikePostResponse {
                        success: true,
                        message: "Post unliked successfully".to_string(),
                    }))
                } else {
                    Ok(Response::new(UnlikePostResponse {
                        success: false,
                        message: "Like not found".to_string(),
                    }))
                }
            }
            Err(e) => {
                error!("Failed to unlike post: {}", e);
                println!("Failed to unlike post: {}", e);
                Err(e.into())
            }
        }
    }

    async fn get_user_likes(
        &self,
        request: Request<GetUserLikesRequest>,
    ) -> Result<Response<GetUserLikesResponse>, Status> {
        let req = request.into_inner();
        debug!(
            "Get user likes request: user_id={}, page={}, limit={}",
            req.user_id, req.page, req.limit
        );

        let mut user_client = self.user_client.clone();

        if req.user_id.trim().is_empty() {
            return Err(Status::invalid_argument("User ID cannot be empty"));
        }

        let user = user_client
            .get_user(req.user_id.clone())
            .await
            .map_err(|e| Status::internal(format!("Failed to get user details: {}", e)))?;

        let db_user_id = user
            .user
            .as_ref()
            .ok_or_else(|| Status::not_found("User not found"))?
            .id
            .clone();

        let params = PaginationParams::new(req.page, req.limit);

        match self.repository.get_user_likes(&db_user_id, &params).await {
            Ok(result) => {
                let likes: Vec<UserLike> = result
                    .data
                    .into_iter()
                    .map(|like| UserLike {
                        post_id: like.post_id,
                        liked_at: Some(Self::datetime_to_timestamp(like.liked_at)),
                    })
                    .collect();

                Ok(Response::new(GetUserLikesResponse {
                    likes,
                    pagination: Some(PaginationInfo {
                        current_page: result.current_page,
                        total_pages: result.total_pages,
                        total_count: result.total_count,
                        limit: result.limit,
                    }),
                }))
            }
            Err(e) => {
                error!("Failed to get user likes: {}", e);
                println!("Failed to get user likes: {}", e);
                Err(e.into())
            }
        }
    }

    async fn get_post_likes(
        &self,
        request: Request<GetPostLikesRequest>,
    ) -> Result<Response<GetPostLikesResponse>, Status> {
        let req = request.into_inner();
        debug!(
            "Get post likes request: post_id={}, page={}, limit={}",
            req.post_id, req.page, req.limit
        );

        if req.post_id <= 0 {
            return Err(Status::invalid_argument(
                "Post ID must be a positive integer",
            ));
        }

        let params = PaginationParams::new(req.page, req.limit);

        match self.repository.get_post_likes(&req.post_id, &params).await {
            Ok(result) => {
                let likes: Vec<PostLike> = result
                    .data
                    .into_iter()
                    .map(|like| PostLike {
                        user_id: like.user_id,
                        liked_at: Some(Self::datetime_to_timestamp(like.liked_at)),
                    })
                    .collect();

                Ok(Response::new(GetPostLikesResponse {
                    likes,
                    pagination: Some(PaginationInfo {
                        current_page: result.current_page,
                        total_pages: result.total_pages,
                        total_count: result.total_count,
                        limit: result.limit,
                    }),
                }))
            }
            Err(e) => {
                error!("Failed to get post likes: {}", e);
                Err(e.into())
            }
        }
    }

    async fn is_post_liked(
        &self,
        request: Request<IsPostLikedRequest>,
    ) -> Result<Response<IsPostLikedResponse>, Status> {
        let req = request.into_inner();
        debug!(
            "Is post liked request: user_id={}, post_id={}",
            req.user_id, req.post_id
        );

        let mut user_client = self.user_client.clone();

        Self::validate_ids(&req.user_id, &req.post_id)?;

        let user = user_client
            .get_user(req.user_id.clone())
            .await
            .map_err(|e| Status::internal(format!("Failed to get user details: {}", e)))?;

        let db_user_id = user
            .user
            .as_ref()
            .ok_or_else(|| Status::not_found("User not found"))?
            .id
            .clone();

        match self
            .repository
            .is_post_liked(&db_user_id, &req.post_id)
            .await
        {
            Ok(liked_at) => Ok(Response::new(IsPostLikedResponse {
                is_liked: liked_at.is_some(),
                liked_at: liked_at.map(Self::datetime_to_timestamp),
            })),
            Err(e) => {
                error!("Failed to check if post is liked: {}", e);
                Err(e.into())
            }
        }
    }

    async fn get_likes_count(
        &self,
        request: Request<GetLikesCountRequest>,
    ) -> Result<Response<GetLikesCountResponse>, Status> {
        let req = request.into_inner();
        debug!("Get likes count request: post_id={}", req.post_id);

        if req.post_id <= 0 {
            return Err(Status::invalid_argument(
                "Post ID must be a positive integer",
            ));
        }

        match self.repository.get_likes_count(&req.post_id).await {
            Ok(count) => Ok(Response::new(GetLikesCountResponse { count })),
            Err(e) => {
                error!("Failed to get likes count: {}", e);
                Err(e.into())
            }
        }
    }

    async fn unlike_posts(
        &self,
        request: Request<UnlikePostsRequest>,
    ) -> Result<Response<UnlikePostResponse>, Status> {
        let req = request.into_inner();
        debug!(
            "Unlike posts request for {} users and {} posts",
            req.user_ids.len(),
            req.post_ids.len()
        );
        let mut user_client = self.user_client.clone();

        if req.user_ids.is_empty() && req.post_ids.is_empty() {
            return Err(Status::invalid_argument(
                "User IDs and Post IDs cannot be empty",
            ));
        }

        // Validate user IDs
        for user_id in &req.user_ids {
            if user_id.trim().is_empty() {
                return Err(Status::invalid_argument("User ID cannot be empty"));
            }
        }

        let mut db_user_ids = Vec::with_capacity(req.user_ids.len());
        if !req.user_ids.is_empty() {
            for external_user_id in &req.user_ids {
                let user_resp = user_client
                    .get_user(external_user_id.clone())
                    .await
                    .map_err(|e| Status::internal(format!("Failed to get user details: {}", e)))?;

                let db_user_id = user_resp
                    .user
                    .as_ref()
                    .ok_or_else(|| Status::not_found("User not found"))?
                    .id
                    .clone();

                db_user_ids.push(db_user_id);
            }
        }

        // Validate post IDs
        for post_id in &req.post_ids {
            if *post_id <= 0 {
                return Err(Status::invalid_argument(
                    "Post ID must be a positive integer",
                ));
            }
        }

        match self
            .repository
            .unlike_posts(&db_user_ids, &req.post_ids)
            .await
        {
            Ok(deleted) => Ok(Response::new(UnlikePostResponse {
                success: deleted,
                message: if deleted {
                    "Posts unliked successfully".to_string()
                } else {
                    "No likes found to unlike".to_string()
                },
            })),
            Err(e) => {
                error!("Failed to unlike posts: {}", e);
                Err(e.into())
            }
        }
    }

    async fn health_check(
        &self,
        _request: Request<HealthCheckRequest>,
    ) -> Result<Response<HealthCheckResponse>, Status> {
        debug!("Health check request");

        match self.repository.health_check().await {
            Ok(_) => Ok(Response::new(HealthCheckResponse {
                status: "healthy".to_string(),
                timestamp: Some(Self::datetime_to_timestamp(chrono::Utc::now())),
            })),
            Err(e) => {
                error!("Health check failed: {}", e);
                Err(Status::internal("Service unhealthy"))
            }
        }
    }
}
