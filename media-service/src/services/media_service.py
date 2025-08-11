"""Media service implementation with gRPC interface."""
from typing import Any, Dict, List
import grpc
from concurrent import futures

from src.generated import media_pb2, media_pb2_grpc
from src.repository.media_repository import MediaRepository
from src.utils.logger import LoggerMixin
from src.utils.exceptions import (
    MediaServiceError,
    FileNotFoundError,
    InvalidFileError,
    FileSizeExceededError,
    BatchOperationError,
    convert_to_grpc_error,
)
from src.config.settings import settings


class MediaServiceImpl(media_pb2_grpc.MediaServiceServicer, LoggerMixin):
    """Implementation of the MediaService gRPC interface."""
    
    def __init__(self):
        """Initialize the media service."""
        self.imagekit_client = MediaRepository()
        self.logger.info("MediaService initialized")
    
    def GetUploadAuth(
        self, 
        request: media_pb2.GetUploadAuthRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.GetUploadAuthResponse:
        """Get upload authentication parameters."""
        try:
            self.logger.info("Processing GetUploadAuth request")
            auth_params = self.imagekit_client.get_authentication_parameters()
            
            return media_pb2.GetUploadAuthResponse(
                token=auth_params["token"],
                expire=auth_params["expire"],
                signature=auth_params["signature"],
                public_key=settings.imagekit_public_key,
                success=True,
                error_message=""
            )
                    
        except Exception as e:
            self.logger.error("GetFiles failed", error=str(e))
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.GetFilesResponse(
                success=False,
                error_message=str(e)
            )
    
    def DeleteFile(
        self, 
        request: media_pb2.DeleteFileRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.DeleteFileResponse:
        """Delete a single file."""
        try:
            if not request.file_id:
                raise InvalidFileError("File ID is required")
            
            self.logger.info("Processing DeleteFile request", file_id=request.file_id)
            self.imagekit_client.delete_file(request.file_id)
            
            return media_pb2.DeleteFileResponse(
                success=True,
                error_message=""
            )
            
        except Exception as e:
            self.logger.error("DeleteFile failed", error=str(e), file_id=request.file_id)
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.DeleteFileResponse(
                success=False,
                error_message=str(e)
            )
    
    def DeleteMultipleFiles(
        self, 
        request: media_pb2.DeleteMultipleFilesRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.DeleteMultipleFilesResponse:
        """Delete multiple files."""
        try:
            if not request.file_ids:
                raise InvalidFileError("At least one file ID is required")
            
            file_ids = list(request.file_ids)
            self.logger.info("Processing DeleteMultipleFiles request", file_count=len(file_ids))
            
            results = self.imagekit_client.bulk_delete_files(file_ids)
            
            # Convert to protobuf format
            delete_results = []
            all_success = True
            for result in results:
                delete_result = media_pb2.DeleteResult(
                    file_id=result["file_id"],
                    success=result["success"],
                    error_message=result["error_message"]
                )
                delete_results.append(delete_result)
                if not result["success"]:
                    all_success = False
            
            return media_pb2.DeleteMultipleFilesResponse(
                results=delete_results,
                all_success=all_success,
                error_message="" if all_success else "Some files failed to delete"
            )
            
        except Exception as e:
            self.logger.error("DeleteMultipleFiles failed", error=str(e))
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.DeleteMultipleFilesResponse(
                all_success=False,
                error_message=str(e)
            )
    
    def UploadFile(
        self, 
        request: media_pb2.UploadFileRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.UploadFileResponse:
        """Upload a file."""
        try:
            if not request.file_data:
                raise InvalidFileError("File data is required")
            if not request.filename:
                raise InvalidFileError("Filename is required")
            
            self.logger.info(
                "Processing UploadFile request",
                filename=request.filename,
                folder=request.folder or None,
                tags=list(request.tags) if request.tags else None
            )
            
            file_details = self.imagekit_client.upload_file(
                file_data=request.file_data,
                filename=request.filename,
                folder=request.folder or None,
                tags=list(request.tags) if request.tags else None,
                use_unique_filename=request.use_unique_filename,
                custom_coordinates=request.custom_coordinates or None,
            )
            
            return media_pb2.UploadFileResponse(
                file=self._dict_to_file_details(file_details),
                success=True,
                error_message=""
            )
            
        except Exception as e:
            self.logger.error("UploadFile failed", error=str(e), filename=request.filename)
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.UploadFileResponse(
                success=False,
                error_message=str(e)
            )
    
    def UpdateFileDetails(
        self, 
        request: media_pb2.UpdateFileDetailsRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.UpdateFileDetailsResponse:
        """Update file details."""
        try:
            if not request.file_id:
                raise InvalidFileError("File ID is required")
            
            self.logger.info(
                "Processing UpdateFileDetails request",
                file_id=request.file_id,
                tags=list(request.tags) if request.tags else None
            )
            
            file_details = self.imagekit_client.update_file_details(
                file_id=request.file_id,
                tags=list(request.tags) if request.tags else None,
                custom_coordinates=request.custom_coordinates or None,
                custom_metadata=dict(request.custom_metadata) if request.custom_metadata else None,
            )
            
            return media_pb2.UpdateFileDetailsResponse(
                file=self._dict_to_file_details(file_details),
                success=True,
                error_message=""
            )
            
        except Exception as e:
            self.logger.error("UpdateFileDetails failed", error=str(e), file_id=request.file_id)
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.UpdateFileDetailsResponse(
                success=False,
                error_message=str(e)
            )
    
    def _dict_to_file_details(self, file_dict: Dict[str, Any]) -> media_pb2.FileDetails:
        """Convert dictionary to FileDetails protobuf message."""
        return media_pb2.FileDetails(
            file_id=file_dict.get("file_id", ""),
            name=file_dict.get("name", ""),
            url=file_dict.get("url", ""),
            thumbnail_url=file_dict.get("thumbnail_url", ""),
            size=file_dict.get("size", 0),
            file_type=file_dict.get("file_type", ""),
            tags=file_dict.get("tags", []),
            folder_path=file_dict.get("folder_path", ""),
            created_at=file_dict.get("created_at", ""),
            updated_at=file_dict.get("updated_at", ""),
            width=file_dict.get("width", 0),
            height=file_dict.get("height", 0),
            custom_metadata=file_dict.get("custom_metadata", {}),
        )

    def GetFileDetails(
        self, 
        request: media_pb2.GetFileDetailsRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.GetFileDetailsResponse:
        """Get details of a specific file."""
        try:
            if not request.file_id:
                raise InvalidFileError("File ID is required")
            
            self.logger.info("Processing GetFileDetails request", file_id=request.file_id)
            file_details = self.imagekit_client.get_file_details(request.file_id)
            
            return media_pb2.GetFileDetailsResponse(
                file=self._dict_to_file_details(file_details),
                success=True,
                error_message=""
            )
            
        except Exception as e:
            self.logger.error("GetFileDetails failed", error=str(e), file_id=request.file_id)
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.GetFileDetailsResponse(
                success=False,
                error_message=str(e)
            )
    
    def GetFiles(
        self, 
        request: media_pb2.GetFilesRequest, 
        context: grpc.ServicerContext
    ) -> media_pb2.GetFilesResponse:
        """Get list of files with optional filters."""
        try:
            self.logger.info(
                "Processing GetFiles request",
                skip=request.skip,
                limit=request.limit,
                search_query=request.search_query or None,
                tags=list(request.tags) if request.tags else None,
                file_type=request.file_type or None
            )
            
            # Validate parameters
            if request.limit <= 0:
                request.limit = 1000
            if request.skip < 0:
                request.skip = 0
            
            result = self.imagekit_client.list_files(
                skip=request.skip,
                limit=request.limit,
                search_query=request.search_query or None,
                tags=list(request.tags) if request.tags else None,
                file_type=request.file_type or None,
                sort=request.sort or None,
                path=request.path or None,
            )
            
            files = [self._dict_to_file_details(file_dict) for file_dict in result["files"]]
            
            return media_pb2.GetFilesResponse(
                files=files,
                success=True,
                error_message="",
                total_count=result.get("total_count", len(files))
            )
        except Exception as e:
            self.logger.error("GetFiles failed", error=str(e))
            context.set_code(convert_to_grpc_error(e))
            context.set_details(str(e))
            return media_pb2.GetFilesResponse(
                success=False,
                error_message=str(e),
                total_count=0,
                files=[]
            )