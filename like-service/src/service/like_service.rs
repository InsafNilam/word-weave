use crate::{
    models::PaginationParams,
    proto::{likes_service_server::LikesService, *},
    repository::LikesRepository,
};
use std::collections::HashMap;
use tonic::{Request, Response, Status};
use tracing::{debug, error, info};

#[derive(Debug)]
pub struct LikesServiceImpl {
    repository: LikesRepository,
}

impl LikesServiceImpl {
    pub fn new(repository: LikesRepository) -> Self {
        Self { repository }
    }

    fn validate_ids(user_id: &str, post_id: &str) -> Result<(), Status> {
        if user_id.trim().is_empty() {
            return Err(Status::invalid_argument("User ID cannot be empty"));
        }
        if post_id.trim().is_empty() {
            return Err(Status::invalid_argument("Post ID cannot be empty"));
        }
        Ok(())
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

        match self
            .repository
            .create_like(&req.user_id, &req.post_id)
            .await
        {
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

        Self::validate_ids(&req.user_id, &req.post_id)?;

        match self
            .repository
            .delete_like(&req.user_id, &req.post_id)
            .await
        {
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

        if req.user_id.trim().is_empty() {
            return Err(Status::invalid_argument("User ID cannot be empty"));
        }

        let params = PaginationParams::new(req.page, req.limit);

        match self.repository.get_user_likes(&req.user_id, &params).await {
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

        if req.post_id.trim().is_empty() {
            return Err(Status::invalid_argument("Post ID cannot be empty"));
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

        Self::validate_ids(&req.user_id, &req.post_id)?;

        match self
            .repository
            .is_post_liked(&req.user_id, &req.post_id)
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

        if req.post_id.trim().is_empty() {
            return Err(Status::invalid_argument("Post ID cannot be empty"));
        }

        match self.repository.get_likes_count(&req.post_id).await {
            Ok(count) => Ok(Response::new(GetLikesCountResponse { count })),
            Err(e) => {
                error!("Failed to get likes count: {}", e);
                Err(e.into())
            }
        }
    }

    async fn get_likes_count_bulk(
        &self,
        request: Request<GetLikesCountBulkRequest>,
    ) -> Result<Response<GetLikesCountBulkResponse>, Status> {
        let req = request.into_inner();
        debug!(
            "Get bulk likes count request for {} posts",
            req.post_ids.len()
        );

        if req.post_ids.is_empty() {
            return Ok(Response::new(GetLikesCountBulkResponse {
                counts: HashMap::new(),
            }));
        }

        // Validate post IDs
        for post_id in &req.post_ids {
            if post_id.trim().is_empty() {
                return Err(Status::invalid_argument("Post ID cannot be empty"));
            }
        }

        match self.repository.get_likes_count_bulk(&req.post_ids).await {
            Ok(counts) => Ok(Response::new(GetLikesCountBulkResponse { counts })),
            Err(e) => {
                error!("Failed to get bulk likes count: {}", e);
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

        // Validate post IDs
        for post_id in &req.post_ids {
            if post_id.trim().is_empty() {
                return Err(Status::invalid_argument("Post ID cannot be empty"));
            }
        }

        match self
            .repository
            .unlike_posts(&req.user_ids, &req.post_ids)
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
