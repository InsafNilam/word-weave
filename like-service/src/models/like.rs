use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Like {
    pub id: Option<String>,
    pub user_id: String,
    pub post_id: String,
    pub liked_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Like {
    pub fn new(user_id: String, post_id: String) -> Self {
        let now = Utc::now();
        Self {
            id: Some(Uuid::new_v4().to_string()),
            user_id,
            post_id,
            liked_at: now,
            created_at: now,
            updated_at: now,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikeCount {
    pub post_id: String,
    pub count: i64,
}

#[derive(Debug, Clone)]
pub struct PaginationParams {
    pub page: i32,
    pub limit: i32,
}

impl PaginationParams {
    pub fn new(page: i32, limit: i32) -> Self {
        let page = if page < 1 { 1 } else { page };
        let limit = if limit < 1 {
            10
        } else if limit > 100 {
            100
        } else {
            limit
        };

        Self { page, limit }
    }

    pub fn offset(&self) -> i32 {
        (self.page - 1) * self.limit
    }
}

#[derive(Debug, Clone)]
pub struct PaginatedResult<T> {
    pub data: Vec<T>,
    pub total_count: i64,
    pub current_page: i32,
    pub total_pages: i32,
    pub limit: i32,
}

impl<T> PaginatedResult<T> {
    pub fn new(data: Vec<T>, total_count: i64, params: &PaginationParams) -> Self {
        let total_pages = ((total_count as f64) / (params.limit as f64)).ceil() as i32;

        Self {
            data,
            total_count,
            current_page: params.page,
            total_pages,
            limit: params.limit,
        }
    }
}
