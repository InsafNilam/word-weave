-- init.sql - MySQL initialization script
-- This file will be automatically executed when the MySQL container starts

USE comment_db;

-- Create comments table
CREATE TABLE IF NOT EXISTS comments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    post_id INT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Indexes for better performance
    INDEX IX_Comments_UserId (user_id),
    INDEX IX_Comments_PostId (post_id),
    INDEX IX_Comments_CreatedAt (created_at),
    INDEX IX_Comments_PostId_CreatedAt (post_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;