using CommentService.Grpc;
using CommentService.Models;
using CommentService.Repositories;
using CommentService.Services;
using Grpc.Core;

namespace CommentService.GrpcServices
{
    public class CommentGrpcService : CommentService.Grpc.CommentService.CommentServiceBase
    {
        private readonly ICommentRepository _commentRepository;
        private readonly IExternalServices _externalServices;
        private readonly ILogger<CommentGrpcService> _logger;

        public CommentGrpcService(
            ICommentRepository commentRepository,
            IExternalServices externalServices,
            ILogger<CommentGrpcService> logger)
        {
            _commentRepository = commentRepository;
            _externalServices = externalServices;
            _logger = logger;
        }

        public override async Task<CommentResponse> CreateComment(CreateCommentRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogInformation("Creating comment for user {UserId} on post {PostId}", request.UserId, request.PostId);

                // Validate input
                if (string.IsNullOrWhiteSpace(request.UserId))
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "User ID is required"
                    };
                }

                if (request.PostId <= 0)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Valid Post ID is required"
                    };
                }

                if (string.IsNullOrWhiteSpace(request.Description) || request.Description.Length > 1000)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Description is required and must be less than 1000 characters"
                    };
                }

                // Validate user exists
                var isValidUser = await _externalServices.ValidateUserAsync(request.UserId);
                if (!isValidUser)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Invalid or non-existent user"
                    };
                }

                // Validate post exists
                var isValidPost = await _externalServices.ValidatePostAsync(request.PostId);
                if (!isValidPost)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Invalid or non-existent post"
                    };
                }

                // Create comment
                var comment = new CommentService.Models.Comment
                {
                    UserId = request.UserId,
                    PostId = request.PostId,
                    Description = request.Description.Trim()
                };

                var createdComment = await _commentRepository.CreateAsync(comment);

                return new CommentResponse
                {
                    Success = true,
                    Message = "Comment created successfully",
                    Comment = MapToGrpcComment(createdComment)
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating comment for user {UserId} on post {PostId}", request.UserId, request.PostId);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<CommentResponse> GetComment(GetCommentRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogDebug("Getting comment {CommentId}", request.Id);

                if (request.Id <= 0)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Valid Comment ID is required"
                    };
                }

                var comment = await _commentRepository.GetByIdAsync(request.Id);
                if (comment == null)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Comment not found"
                    };
                }

                return new CommentResponse
                {
                    Success = true,
                    Message = "Comment retrieved successfully",
                    Comment = MapToGrpcComment(comment)
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting comment {CommentId}", request.Id);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<GetCommentsResponse> GetCommentsByPost(GetCommentsByPostRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogDebug("Getting comments for post {PostId}, page {Page}", request.PostId, request.Page);

                if (request.PostId <= 0)
                {
                    return new GetCommentsResponse
                    {
                        Success = false,
                        Message = "Valid Post ID is required"
                    };
                }

                var page = Math.Max(1, request.Page);
                var pageSize = Math.Min(Math.Max(1, request.PageSize), 100); // Limit to 100 items per page

                var (comments, totalCount) = await _commentRepository.GetByPostIdAsync(request.PostId, page, pageSize);

                var response = new GetCommentsResponse
                {
                    Success = true,
                    Message = "Comments retrieved successfully",
                    TotalCount = totalCount,
                    Page = page,
                    PageSize = pageSize
                };

                response.Comments.AddRange(comments.Select(MapToGrpcComment));
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting comments for post {PostId}", request.PostId);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<GetCommentsResponse> GetCommentsByUser(GetCommentsByUserRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogDebug("Getting comments for user {UserId}, page {Page}", request.UserId, request.Page);

                if (string.IsNullOrWhiteSpace(request.UserId))
                {
                    return new GetCommentsResponse
                    {
                        Success = false,
                        Message = "User ID is required"
                    };
                }

                var page = Math.Max(1, request.Page);
                var pageSize = Math.Min(Math.Max(1, request.PageSize), 100);

                var (comments, totalCount) = await _commentRepository.GetByUserIdAsync(request.UserId, page, pageSize);

                var response = new GetCommentsResponse
                {
                    Success = true,
                    Message = "Comments retrieved successfully",
                    TotalCount = totalCount,
                    Page = page,
                    PageSize = pageSize
                };

                response.Comments.AddRange(comments.Select(MapToGrpcComment));
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting comments for user {UserId}", request.UserId);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<CommentResponse> UpdateComment(UpdateCommentRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogInformation("Updating comment {CommentId} by user {UserId}", request.Id, request.UserId);

                if (request.Id <= 0)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Valid Comment ID is required"
                    };
                }

                if (string.IsNullOrWhiteSpace(request.UserId))
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "User ID is required"
                    };
                }

                if (string.IsNullOrWhiteSpace(request.Description) || request.Description.Length > 1000)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Description is required and must be less than 1000 characters"
                    };
                }

                // Get existing comment to verify ownership
                var existingComment = await _commentRepository.GetByIdAsync(request.Id);
                if (existingComment == null)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Comment not found"
                    };
                }

                // Verify user owns the comment
                if (existingComment.UserId != request.UserId)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Unauthorized: You can only update your own comments"
                    };
                }

                // Update comment
                existingComment.Description = request.Description.Trim();
                var updatedComment = await _commentRepository.UpdateAsync(existingComment);

                if (updatedComment == null)
                {
                    return new CommentResponse
                    {
                        Success = false,
                        Message = "Failed to update comment"
                    };
                }

                return new CommentResponse
                {
                    Success = true,
                    Message = "Comment updated successfully",
                    Comment = MapToGrpcComment(updatedComment)
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating comment {CommentId}", request.Id);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<DeleteCommentResponse> DeleteComment(DeleteCommentRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogInformation("Deleting comment {CommentId} by user {UserId}", request.Id, request.UserId);

                if (request.Id <= 0)
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "Valid Comment ID is required"
                    };
                }

                if (string.IsNullOrWhiteSpace(request.UserId))
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "User ID is required"
                    };
                }

                // Get existing comment to verify ownership
                var existingComment = await _commentRepository.GetByIdAsync(request.Id);
                if (existingComment == null)
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "Comment not found"
                    };
                }

                // Verify user owns the comment
                if (existingComment.UserId != request.UserId)
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "Unauthorized: You can only delete your own comments"
                    };
                }

                var deleted = await _commentRepository.DeleteAsync(request.Id);
                if (!deleted)
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "Failed to delete comment"
                    };
                }

                return new DeleteCommentResponse
                {
                    Success = true,
                    Message = "Comment deleted successfully"
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting comment {CommentId}", request.Id);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<GetCommentCountResponse> GetCommentCount(GetCommentCountRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogDebug("Getting comment count for post {PostId}", request.PostId);

                if (request.PostId <= 0)
                {
                    return new GetCommentCountResponse
                    {
                        Success = false,
                        Message = "Valid Post ID is required"
                    };
                }

                var count = await _commentRepository.GetCommentCountByPostIdAsync(request.PostId);

                return new GetCommentCountResponse
                {
                    Success = true,
                    Message = "Comment count retrieved successfully",
                    Count = count
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting comment count for post {PostId}", request.PostId);
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        public override async Task<DeleteCommentResponse> DeleteComments(DeleteCommentsRequest request, ServerCallContext context)
        {
            try
            {
                _logger.LogInformation("Deleting comments — Users: {UserIds}, Posts: {PostIds}",
                    request.UserIds.Count, request.PostIds.Count);

                // Validate input
                if ((request.UserIds == null || request.UserIds.Count == 0) &&
                    (request.PostIds == null || request.PostIds.Count == 0))
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "At least one of Ids, UserIds, or PostIds must be provided"
                    };
                }

                // Pass to repository to handle conditional deletion
                bool deletedCount = await _commentRepository.DeleteMultipleAsync(
                    request.UserIds != null ? request.UserIds.ToList() : new List<string>(),
                    request.PostIds != null ? request.PostIds.ToList() : new List<uint>()
                );

                if (!deletedCount)
                {
                    return new DeleteCommentResponse
                    {
                        Success = false,
                        Message = "No comments deleted"
                    };
                }

                return new DeleteCommentResponse
                {
                    Success = true,
                    Message = $"{deletedCount} comments deleted successfully"
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting comments");
                throw new RpcException(new Status(StatusCode.Internal, "Internal server error"));
            }
        }

        private static Grpc.Comment MapToGrpcComment(Models.Comment comment)
        {
            return new Grpc.Comment
            {
                Id = comment.Id,
                UserId = comment.UserId,
                PostId = comment.PostId,
                Description = comment.Description,
                CreatedAt = comment.CreatedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
                UpdatedAt = comment.UpdatedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            };
        }
    }
}