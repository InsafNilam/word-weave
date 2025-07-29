"""ImageKit client wrapper with error handling and logging."""
from typing import Dict, List, Optional, Any, Union
import base64
from imagekitio import ImageKit
from imagekitio.models.UploadFileRequestOptions import UploadFileRequestOptions
from imagekitio.models.ListAndSearchFileRequestOptions import ListAndSearchFileRequestOptions

from src.config.settings import settings
from src.utils.logger import LoggerMixin
from src.utils.exceptions import ImageKitError, FileNotFoundError, FileSizeExceededError


class MediaRepository(LoggerMixin):
    """Production-ready ImageKit client wrapper."""
    
    def __init__(self):
        """Initialize ImageKit client."""
        try:
            self.client = ImageKit(
                private_key=settings.imagekit_private_key,
                public_key=settings.imagekit_public_key,
                url_endpoint=settings.imagekit_url_endpoint,
            )
            self.logger.info("ImageKit client initialized successfully")
        except Exception as e:
            self.logger.error("Failed to initialize ImageKit client", error=str(e))
            raise ImageKitError(f"Failed to initialize ImageKit client: {str(e)}")
    
    def get_authentication_parameters(self) -> Dict[str, Any]:
        """Get authentication parameters for client-side uploads."""
        try:
            auth_params = self.client.get_authentication_parameters()
            self.logger.info("Generated authentication parameters")
            return {
                "token": auth_params["token"],
                "expire": auth_params["expire"],
                "signature": auth_params["signature"]
            }
        except Exception as e:
            self.logger.error("Failed to get authentication parameters", error=str(e))
            raise ImageKitError(f"Failed to get authentication parameters: {str(e)}")
    
    def upload_file(
        self,
        file_data: bytes,
        filename: str,
        folder: Optional[str] = None,
        tags: Optional[List[str]] = None,
        use_unique_filename: bool = True,
        custom_coordinates: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Upload a file to ImageKit."""
        try:
            # Check file size
            file_size_mb = len(file_data) / (1024 * 1024)
            if file_size_mb > settings.max_file_size_mb:
                raise FileSizeExceededError(
                    f"File size {file_size_mb:.2f}MB exceeds limit of {settings.max_file_size_mb}MB"
                )
            
            # Prepare upload options
            options = UploadFileRequestOptions(
                use_unique_file_name=use_unique_filename,
                tags=tags,
                folder=folder,
                custom_coordinates=custom_coordinates,
            )
            
            # Convert bytes to base64 string
            file_base64 = base64.b64encode(file_data).decode('utf-8')
            
            self.logger.info(
                "Uploading file",
                filename=filename,
                size_mb=f"{file_size_mb:.2f}",
                folder=folder,
                tags=tags
            )
            
            result = self.client.upload_file(
                file=file_base64,
                file_name=filename,
                options=options
            )
            
            if result.response_metadata.http_status_code != 200:
                raise ImageKitError(f"Upload failed: {result.response_metadata.raw}")
            
            self.logger.info("File uploaded successfully", file_id=result.file_id)
            return self._format_file_details(result)
            
        except FileSizeExceededError:
            raise
        except Exception as e:
            self.logger.error("File upload failed", error=str(e), filename=filename)
            raise ImageKitError(f"File upload failed: {str(e)}")
    
    def get_file_details(self, file_id: str) -> Dict[str, Any]:
        """Get details of a specific file."""
        try:
            self.logger.info("Fetching file details", file_id=file_id)
            result = self.client.get_file_details(file_id)
            
            if result.response_metadata.http_status_code == 404:
                raise FileNotFoundError(f"File not found: {file_id}")
            elif result.response_metadata.http_status_code != 200:
                raise ImageKitError(f"Failed to get file details: {result.response_metadata.raw}")
            
            self.logger.info("File details retrieved", file_id=file_id)
            return self._format_file_details(result)
            
        except FileNotFoundError:
            raise
        except Exception as e:
            self.logger.error("Failed to get file details", error=str(e), file_id=file_id)
            raise ImageKitError(f"Failed to get file details: {str(e)}")
    
    def list_files(
        self,
        skip: int = 0,
        limit: int = 1000,
        search_query: Optional[str] = None,
        tags: Optional[List[str]] = None,
        file_type: Optional[str] = None,
        sort: Optional[str] = None,
        path: Optional[str] = None,
    ) -> Dict[str, Any]:
        """List files with optional filters."""
        try:
            options = ListAndSearchFileRequestOptions(
                type=file_type,
                sort=sort,
                path=path,
                search_query=search_query,
                file_type=file_type,
                tags=",".join(tags) if tags else None,
                limit=limit,
                skip=skip,
            )
            
            self.logger.info(
                "Listing files",
                skip=skip,
                limit=limit,
                search_query=search_query,
                tags=tags,
                file_type=file_type
            )
            
            result = self.client.list_files(options)
            
            if result.response_metadata.http_status_code != 200:
                raise ImageKitError(f"Failed to list files: {result.response_metadata.raw}")
            
            files = [self._format_file_details(file) for file in result.list]
            
            self.logger.info("Files listed successfully", count=len(files))
            return {
                "files": files,
                "total_count": getattr(result, 'total_count', len(files))
            }
            
        except Exception as e:
            self.logger.error("Failed to list files", error=str(e))
            raise ImageKitError(f"Failed to list files: {str(e)}")
    
    def delete_file(self, file_id: str) -> bool:
        """Delete a single file."""
        try:
            self.logger.info("Deleting file", file_id=file_id)
            result = self.client.delete_file(file_id)
            
            if result.response_metadata.http_status_code == 404:
                raise FileNotFoundError(f"File not found: {file_id}")
            elif result.response_metadata.http_status_code != 204:
                raise ImageKitError(f"Failed to delete file: {result.response_metadata.raw}")
            
            self.logger.info("File deleted successfully", file_id=file_id)
            return True
            
        except FileNotFoundError:
            raise
        except Exception as e:
            self.logger.error("Failed to delete file", error=str(e), file_id=file_id)
            raise ImageKitError(f"Failed to delete file: {str(e)}")
    
    def bulk_delete_files(self, file_ids: List[str]) -> List[Dict[str, Any]]:
        """Delete multiple files in bulk."""
        try:
            if len(file_ids) > settings.max_files_per_batch_delete:
                raise ImageKitError(
                    f"Cannot delete more than {settings.max_files_per_batch_delete} files at once"
                )
            
            self.logger.info("Bulk deleting files", file_count=len(file_ids))
            result = self.client.bulk_file_delete(file_ids)
            
            if result.response_metadata.http_status_code != 200:
                raise ImageKitError(f"Bulk delete failed: {result.response_metadata.raw}")
            
            # Process results
            results = []
            successful_deletes = result.successfully_deleted_file_ids or []
            
            for file_id in file_ids:
                if file_id in successful_deletes:
                    results.append({
                        "file_id": file_id,
                        "success": True,
                        "error_message": ""
                    })
                else:
                    # Find error message from missing files
                    error_msg = "Unknown error"
                    if hasattr(result, 'missing_file_ids') and file_id in result.missing_file_ids:
                        error_msg = "File not found"
                    
                    results.append({
                        "file_id": file_id,
                        "success": False,
                        "error_message": error_msg
                    })
            
            success_count = len(successful_deletes)
            self.logger.info(
                "Bulk delete completed",
                total=len(file_ids),
                successful=success_count,
                failed=len(file_ids) - success_count
            )
            
            return results
            
        except Exception as e:
            self.logger.error("Bulk delete failed", error=str(e))
            raise ImageKitError(f"Bulk delete failed: {str(e)}")
    
    def update_file_details(
        self,
        file_id: str,
        tags: Optional[List[str]] = None,
        custom_coordinates: Optional[str] = None,
        custom_metadata: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """Update file details."""
        try:
            update_data = {}
            if tags is not None:
                update_data["tags"] = tags
            if custom_coordinates is not None:
                update_data["custom_coordinates"] = custom_coordinates
            if custom_metadata is not None:
                update_data["custom_metadata"] = custom_metadata
            
            self.logger.info("Updating file details", file_id=file_id, updates=list(update_data.keys()))
            result = self.client.update_file_details(file_id, update_data)
            
            if result.response_metadata.http_status_code == 404:
                raise FileNotFoundError(f"File not found: {file_id}")
            elif result.response_metadata.http_status_code != 200:
                raise ImageKitError(f"Failed to update file: {result.response_metadata.raw}")
            
            self.logger.info("File details updated successfully", file_id=file_id)
            return self._format_file_details(result)
            
        except FileNotFoundError:
            raise
        except Exception as e:
            self.logger.error("Failed to update file details", error=str(e), file_id=file_id)
            raise ImageKitError(f"Failed to update file details: {str(e)}")
    
    def _format_file_details(self, file_obj: Any) -> Dict[str, Any]:
        """Format file object into a consistent dictionary."""
        return {
            "file_id": getattr(file_obj, 'file_id', ''),
            "name": getattr(file_obj, 'name', ''),
            "url": getattr(file_obj, 'url', ''),
            "thumbnail_url": getattr(file_obj, 'thumbnail_url', ''),
            "size": getattr(file_obj, 'size', 0),
            "file_type": getattr(file_obj, 'file_type', ''),
            "tags": getattr(file_obj, 'tags', []) or [],
            "folder_path": getattr(file_obj, 'folder_path', ''),
            "created_at": getattr(file_obj, 'created_at', ''),
            "updated_at": getattr(file_obj, 'updated_at', ''),
            "width": getattr(file_obj, 'width', 0),
            "height": getattr(file_obj, 'height', 0),
            "custom_metadata": getattr(file_obj, 'custom_metadata', {}) or {},
        }