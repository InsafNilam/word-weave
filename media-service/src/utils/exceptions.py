"""Custom exceptions for the media service."""
from typing import Optional
import grpc


class MediaServiceError(Exception):
    """Base exception for media service errors."""
    
    def __init__(self, message: str, error_code: Optional[str] = None):
        self.message = message
        self.error_code = error_code
        super().__init__(self.message)


class ImageKitError(MediaServiceError):
    """Exception for ImageKit API errors."""
    pass


class FileNotFoundError(MediaServiceError):
    """Exception when a file is not found."""
    pass


class InvalidFileError(MediaServiceError):
    """Exception for invalid file operations."""
    pass


class FileSizeExceededError(MediaServiceError):
    """Exception when file size exceeds limits."""
    pass


class BatchOperationError(MediaServiceError):
    """Exception for batch operation errors."""
    
    def __init__(self, message: str, failed_items: Optional[list] = None):
        super().__init__(message)
        self.failed_items = failed_items or []


def convert_to_grpc_error(error: Exception) -> grpc.StatusCode:
    """Convert Python exceptions to gRPC status codes."""
    if isinstance(error, FileNotFoundError):
        return grpc.StatusCode.NOT_FOUND
    elif isinstance(error, InvalidFileError):
        return grpc.StatusCode.INVALID_ARGUMENT
    elif isinstance(error, FileSizeExceededError):
        return grpc.StatusCode.RESOURCE_EXHAUSTED
    elif isinstance(error, ImageKitError):
        return grpc.StatusCode.EXTERNAL
    elif isinstance(error, BatchOperationError):
        return grpc.StatusCode.FAILED_PRECONDITION
    else:
        return grpc.StatusCode.INTERNAL