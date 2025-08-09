-- Create the comment database (if not exists)
CREATE DATABASE IF NOT EXISTS comment_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Use the comment database
USE comment_db;

-- Create application user with proper permissions
CREATE USER IF NOT EXISTS 'comment_user'@'%' IDENTIFIED BY '5Otsq2k6B4jQ';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON comment_db.* TO 'comment_user'@'%';

-- Create comments table
CREATE TABLE IF NOT EXISTS comments (
    id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    user_id VARCHAR(255) NOT NULL,
    post_id INT UNSIGNED NOT NULL,
    description VARCHAR(1000) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_post_id (post_id),
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at),
    INDEX idx_post_user (post_id, user_id),
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Grant necessary permissions to the application user
FLUSH PRIVILEGES;

-- Print success message
SELECT 'MySQL comment_db initialization completed successfully!' as message;
SELECT 'Created tables: comments' as tables_created;
SELECT 'Created user: comment_user with proper permissions' as user_created;
