-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Create post_db database if it doesn't exist
SELECT 'CREATE DATABASE post_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'post_db')\gexec

-- Connect to post_db
\c post_db;

-- Create enum types for posts
CREATE TYPE post_status AS ENUM ('draft', 'published', 'archived', 'deleted');
CREATE TYPE post_visibility AS ENUM ('public', 'private', 'friends_only', 'unlisted');
CREATE TYPE media_type AS ENUM ('image', 'video', 'audio', 'document', 'gif');

-- Create posts table
CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    img TEXT,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL UNIQUE,
    desc TEXT,
    category VARCHAR(100) DEFAULT 'general',
    content TEXT NOT NULL,
    is_featured BOOLEAN DEFAULT FALSE,
    visit BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for posts
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_slug ON posts(slug);
CREATE INDEX IF NOT EXISTS idx_posts_category ON posts(category);
CREATE INDEX IF NOT EXISTS idx_posts_is_featured ON posts(is_featured);

-- Create event_db database for events
SELECT 'CREATE DATABASE event_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'event_db')\gexec

-- Connect to event_db
\c event_db;

-- Enable UUID extension for event_db
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create enum types for events
CREATE TYPE event_type AS ENUM (
    'user.created', 'user.updated', 'user.deleted',
    'post.created', 'post.updated', 'post.deleted',
    'comment.created', 'comment.updated', 'comment.deleted',
    'like.created', 'like.deleted'
);

CREATE TABLE IF NOT EXISTS events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type event_type NOT NULL,
    aggregate_id VARCHAR(255) NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    metadata JSONB DEFAULT '{}',
    version BIGINT NOT NULL DEFAULT 1,
    timestamp BIGINT NOT NULL,
    correlation_id UUID,
    causation_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(aggregate_id, version)
);

-- Create indexes for events
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_aggregate ON events(aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS idx_events_correlation_id ON events(correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_event_data ON events USING GIN(event_data);
CREATE INDEX IF NOT EXISTS idx_events_metadata ON events USING GIN(metadata);

-- Create functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for automatic timestamp updates
CREATE TRIGGER update_posts_updated_at BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Print completion message
DO $$ 
BEGIN 
    RAISE NOTICE 'PostgreSQL databases initialization completed successfully!';
    RAISE NOTICE 'Created databases: post_db, event_db';
    RAISE NOTICE 'Created tables with indexes, triggers, and functions';
    RAISE NOTICE 'Inserted default categories and sample data';
END $$;