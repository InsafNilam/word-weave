using CommentService.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using System.Text.Json;

namespace CommentService.Repositories
{
    public interface ICommentRepository
    {
        Task<Comment?> GetByIdAsync(int id);
        Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByPostIdAsync(int postId, int page, int pageSize);
        Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByUserIdAsync(string userId, int page, int pageSize);
        Task<Comment> CreateAsync(Comment comment);
        Task<Comment?> UpdateAsync(Comment comment);
        Task<bool> DeleteAsync(int id);
        Task<int> GetCommentCountByPostIdAsync(int postId);
        Task<bool> DeleteMultipleAsync(IEnumerable<string> userIds, IEnumerable<int> postIds);
    }

    public class CommentRepository : ICommentRepository
    {
        private readonly CommentDbContext _context;
        private readonly IDistributedCache _cache;
        private readonly ILogger<CommentRepository> _logger;
        private readonly TimeSpan _cacheDuration = TimeSpan.FromMinutes(15);

        public CommentRepository(
            CommentDbContext context,
            IDistributedCache cache,
            ILogger<CommentRepository> logger)
        {
            _context = context;
            _cache = cache;
            _logger = logger;
        }

        public async Task<Comment?> GetByIdAsync(int id)
        {
            var cacheKey = $"comment:{id}";

            try
            {
                var cachedComment = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedComment))
                {
                    _logger.LogDebug("Cache hit for comment {CommentId}", id);
                    return JsonSerializer.Deserialize<Comment>(cachedComment);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get comment {CommentId} from cache", id);
            }

            var comment = await _context.Comments
                .FirstOrDefaultAsync(c => c.Id == id);

            if (comment != null)
            {
                await SetCacheAsync(cacheKey, comment);
            }

            return comment;
        }

        public async Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByPostIdAsync(int postId, int page, int pageSize)
        {
            var cacheKey = $"comments:post:{postId}:page:{page}:size:{pageSize}";

            try
            {
                var cachedData = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedData))
                {
                    _logger.LogDebug("Cache hit for post comments {PostId}, page {Page}", postId, page);
                    var cached = JsonSerializer.Deserialize<CommentPageResult>(cachedData);
                    return (cached!.Comments, cached.TotalCount);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get post comments from cache for post {PostId}", postId);
            }

            var totalCount = await _context.Comments.CountAsync(c => c.PostId == postId);

            var comments = await _context.Comments
                .Where(c => c.PostId == postId)
                .OrderByDescending(c => c.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            var result = new CommentPageResult { Comments = comments, TotalCount = totalCount };
            await SetCacheAsync(cacheKey, result);

            return (comments, totalCount);
        }

        public async Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByUserIdAsync(string userId, int page, int pageSize)
        {
            var cacheKey = $"comments:user:{userId}:page:{page}:size:{pageSize}";

            try
            {
                var cachedData = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedData))
                {
                    _logger.LogDebug("Cache hit for user comments {UserId}, page {Page}", userId, page);
                    var cached = JsonSerializer.Deserialize<CommentPageResult>(cachedData);
                    return (cached!.Comments, cached.TotalCount);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get user comments from cache for user {UserId}", userId);
            }

            var totalCount = await _context.Comments.CountAsync(c => c.UserId == userId);

            var comments = await _context.Comments
                .Where(c => c.UserId == userId)
                .OrderByDescending(c => c.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            var result = new CommentPageResult { Comments = comments, TotalCount = totalCount };
            await SetCacheAsync(cacheKey, result);

            return (comments, totalCount);
        }

        public async Task<Comment> CreateAsync(Comment comment)
        {
            comment.CreatedAt = DateTime.UtcNow;
            comment.UpdatedAt = DateTime.UtcNow;

            _context.Comments.Add(comment);
            await _context.SaveChangesAsync();

            // Invalidate related caches
            await InvalidatePostCommentsCache(comment.PostId);
            await InvalidateUserCommentsCache(comment.UserId);

            _logger.LogInformation("Created comment {CommentId} for post {PostId}", comment.Id, comment.PostId);
            return comment;
        }

        public async Task<Comment?> UpdateAsync(Comment comment)
        {
            var existingComment = await _context.Comments.FindAsync(comment.Id);
            if (existingComment == null)
                return null;

            existingComment.Description = comment.Description;
            existingComment.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            // Invalidate caches
            await _cache.RemoveAsync($"comment:{comment.Id}");
            await InvalidatePostCommentsCache(existingComment.PostId);
            await InvalidateUserCommentsCache(existingComment.UserId);

            _logger.LogInformation("Updated comment {CommentId}", comment.Id);
            return existingComment;
        }

        public async Task<bool> DeleteAsync(int id)
        {
            var comment = await _context.Comments.FindAsync(id);
            if (comment == null)
                return false;

            _context.Comments.Remove(comment);
            await _context.SaveChangesAsync();

            // Invalidate caches
            await _cache.RemoveAsync($"comment:{id}");
            await InvalidatePostCommentsCache(comment.PostId);
            await InvalidateUserCommentsCache(comment.UserId);

            _logger.LogInformation("Deleted comment {CommentId}", id);
            return true;
        }

        public async Task<int> GetCommentCountByPostIdAsync(int postId)
        {
            var cacheKey = $"comment_count:post:{postId}";

            try
            {
                var cachedCount = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedCount))
                {
                    _logger.LogDebug("Cache hit for comment count for post {PostId}", postId);
                    return JsonSerializer.Deserialize<int>(cachedCount);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get comment count from cache for post {PostId}", postId);
            }

            var count = await _context.Comments.CountAsync(c => c.PostId == postId);
            await SetCacheAsync(cacheKey, count);

            return count;
        }

        public async Task<bool> DeleteMultipleAsync(IEnumerable<string> userIds, IEnumerable<int> postIds)
        {
            if (userIds == null || !userIds.Any() || postIds == null || !postIds.Any())
                return false;

            var commentsToDelete = await _context.Comments
                .Where(c => userIds.Contains(c.UserId) || postIds.Contains(c.PostId))
                .ToListAsync();

            if (!commentsToDelete.Any())
                return false;

            _context.Comments.RemoveRange(commentsToDelete);
            await _context.SaveChangesAsync();

            // Invalidate caches for each deleted comment
            foreach (var comment in commentsToDelete)
            {
                await _cache.RemoveAsync($"comment:{comment.Id}");
                await InvalidatePostCommentsCache(comment.PostId);
                await InvalidateUserCommentsCache(comment.UserId);
            }

            _logger.LogInformation("Deleted multiple comments for users {UserIds} and posts {PostIds}", string.Join(", ", userIds), string.Join(", ", postIds));
            return true;
        }

        private async Task SetCacheAsync<T>(string key, T value)
        {
            try
            {
                var serialized = JsonSerializer.Serialize(value);
                var options = new DistributedCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheDuration
                };
                await _cache.SetStringAsync(key, serialized, options);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to set cache for key {CacheKey}", key);
            }
        }

        private async Task InvalidatePostCommentsCache(int postId)
        {
            // In a production environment, you might want to use a pattern-based cache invalidation
            // For now, we'll remove specific keys that we know about
            var patterns = new[]
            {
                $"comments:post:{postId}:*",
                $"comment_count:post:{postId}"
            };

            foreach (var pattern in patterns)
            {
                try
                {
                    await _cache.RemoveAsync(pattern);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to invalidate cache pattern {Pattern}", pattern);
                }
            }
        }

        private async Task InvalidateUserCommentsCache(string userId)
        {
            var pattern = $"comments:user:{userId}:*";
            try
            {
                await _cache.RemoveAsync(pattern);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to invalidate user cache pattern {Pattern}", pattern);
            }
        }
    }

    public class CommentPageResult
    {
        public IEnumerable<Comment> Comments { get; set; } = new List<Comment>();
        public int TotalCount { get; set; }
    }
}