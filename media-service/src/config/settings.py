"""Configuration settings for the media service."""
import os
from typing import Optional
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings."""
    
    # ImageKit Configuration
    imagekit_private_key: str = Field(..., alias="IK_PRIVATE_KEY")
    imagekit_public_key: str = Field(..., alias="IK_PUBLIC_KEY")
    imagekit_url_endpoint: str = Field(..., alias="IK_URL_ENDPOINT")
    
    # gRPC Server Configuration
    grpc_port: int = Field(50056, env="GRPC_PORT")
    grpc_host: str = Field("0.0.0.0", env="GRPC_HOST")
    max_workers: int = Field(10, env="MAX_WORKERS")
    
    # Logging Configuration
    log_level: str = Field("INFO", env="LOG_LEVEL")
    log_format: str = Field("json", env="LOG_FORMAT")  # json or console
    
    # Application Configuration
    app_name: str = Field("media-service", env="APP_NAME")
    environment: str = Field("development", env="ENVIRONMENT")
    
    # Request limits
    max_file_size_mb: int = Field(100, env="MAX_FILE_SIZE_MB")
    max_files_per_batch_delete: int = Field(100, env="MAX_FILES_PER_BATCH_DELETE")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

# Global settings instance
settings = Settings()