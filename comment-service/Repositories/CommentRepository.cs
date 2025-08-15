using CommentService.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using Serilog;
using StackExchange.Redis;
using System.Text.Json;

namespace CommentService.Repositories
{
    public interface ICommentRepository
    {
        Task<Comment?> GetByIdAsync(uint id);
        Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByPostIdAsync(uint postId, int page, int pageSize);
        Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByUserIdAsync(string userId, int page, int pageSize);
        Task<Comment> CreateAsync(Comment comment);
        Task<Comment?> UpdateAsync(Comment comment);
        Task<bool> DeleteAsync(uint id);
        Task<int> GetCommentCountByPostIdAsync(uint postId);
        Task<bool> DeleteMultipleAsync(IEnumerable<string> userIds, IEnumerable<uint> postIds);
    }

    public class CommentRepository : ICommentRepository
    {
        private readonly CommentDbContext _context;
        private readonly IDistributedCache _cache;
        private readonly IConnectionMultiplexer _redis;
        private readonly IDatabase _database;
        private readonly ILogger<CommentRepository> _logger;
        private readonly TimeSpan _cacheDuration = TimeSpan.FromMinutes(15);
        private readonly string _keyPrefix;

        public CommentRepository(
            CommentDbContext context,
            IDistributedCache cache,
            IConnectionMultiplexer redis,
            ILogger<CommentRepository> logger)
        {
            _context = context;
            _cache = cache;
            _redis = redis;
            _database = redis.GetDatabase();
            _logger = logger;
            _keyPrefix = GetRedisKeyPrefix();
        }

        private string GetRedisKeyPrefix()
        {
            // Extract the key prefix from RedisCache if available
            if (_cache is RedisCache redisCache)
            {
                var options = redisCache.GetType()
                    .GetField("_options", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)?
                    .GetValue(redisCache) as RedisCacheOptions;

                var prefix = options?.InstanceName ?? "";
                _logger.LogInformation("Detected Redis key prefix: '{Prefix}'", prefix);
                return prefix;
            }
            _logger.LogWarning("Could not detect Redis key prefix, using empty string");
            return "";
        }

        public async Task<Comment?> GetByIdAsync(uint id)
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

        public async Task<(IEnumerable<Comment> Comments, int TotalCount)> GetByPostIdAsync(uint postId, int page, int pageSize)
        {
            var cacheKey = $"comments:post:{postId}:page:{page}:size:{pageSize}";
            _logger.LogDebug("Looking for cache key: {CacheKey}", cacheKey);

            try
            {
                var cachedData = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedData))
                {
                    _logger.LogInformation("Cache hit for post comments {PostId}, page {Page} - KEY: {CacheKey}", postId, page, cacheKey);
                    var cached = JsonSerializer.Deserialize<CommentPageResult>(cachedData);

                    // DEBUG: Show what's in cache vs database
                    var dbCount = await _context.Comments.CountAsync(c => c.PostId == postId);
                    _logger.LogWarning("CACHE vs DB MISMATCH - Cache has {CacheCount} comments, DB has {DbCount} comments", cached!.TotalCount, dbCount);

                    return (cached.Comments, cached.TotalCount);
                }
                else
                {
                    _logger.LogDebug("Cache miss for cache key: {CacheKey}", cacheKey);
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

            _logger.LogInformation("Setting cache for key: {CacheKey} with {Count} comments", cacheKey, totalCount);
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

            _logger.LogInformation("Comment saved to database - ID: {CommentId}, PostId: {PostId}", comment.Id, comment.PostId);

            // Verify the comment exists in database immediately
            var verifyCount = await _context.Comments.CountAsync(c => c.PostId == comment.PostId);
            _logger.LogInformation("Database verification - Total comments for post {PostId}: {Count}", comment.PostId, verifyCount);

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

        public async Task<bool> DeleteAsync(uint id)
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

        public async Task<int> GetCommentCountByPostIdAsync(uint postId)
        {
            var cacheKey = $"comment_count:post:{postId}";

            _logger.LogDebug("Getting comment count for post {PostId}, cache key: {CacheKey}", postId, cacheKey);

            try
            {
                var cachedCount = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedCount))
                {
                    var cached = JsonSerializer.Deserialize<int>(cachedCount);
                    _logger.LogDebug("Cache hit for comment count for post {PostId}: {Count}", postId, cached);
                    return cached;
                }
                else
                {
                    _logger.LogDebug("Cache miss for comment count for post {PostId}", postId);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get comment count from cache for post {PostId}", postId);
            }

            _logger.LogDebug("Querying database for comment count for post {PostId}", postId);
            var count = await _context.Comments.CountAsync(c => c.PostId == postId);
            _logger.LogInformation("Database query result - Comment count for post {PostId}: {Count}", postId, count);

            await SetCacheAsync(cacheKey, count);
            _logger.LogDebug("Cached comment count for post {PostId}: {Count}", postId, count);

            return count;
        }

        public async Task<bool> DeleteMultipleAsync(IEnumerable<string> userIds, IEnumerable<uint> postIds)
        {
            if ((userIds == null || !userIds.Any()) && (postIds == null || !postIds.Any()))
                return false;

            var commentsToDelete = await _context.Comments
                .Where(c => (userIds ?? Enumerable.Empty<string>()).Contains(c.UserId) || (postIds ?? Enumerable.Empty<uint>()).Contains(c.PostId))
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

            _logger.LogInformation("Deleted multiple comments for users {UserIds} and posts {PostIds}",
                string.Join(", ", userIds ?? Enumerable.Empty<string>()), string.Join(", ", postIds ?? Enumerable.Empty<uint>()));
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

        private async Task InvalidatePostCommentsCache(uint postId)
        {
            try
            {
                _logger.LogDebug("Starting cache invalidation for post {PostId} with prefix '{Prefix}'", postId, _keyPrefix);

                // Delete ALL possible cache key combinations for this post
                var pageSizes = new[] { 1, 5, 10, 15, 20, 25, 30, 50, 100 }; // Added size:1 since that's what we saw
                var pages = Enumerable.Range(1, 20); // First 20 pages

                var deletedCount = 0;

                // Delete comment list caches - include the prefix in the key
                foreach (var pageSize in pageSizes)
                {
                    foreach (var page in pages)
                    {
                        // Use IDistributedCache.RemoveAsync which should handle the prefix automatically
                        var key = $"comments:post:{postId}:page:{page}:size:{pageSize}";
                        try
                        {
                            await _cache.RemoveAsync(key);
                            deletedCount++;
                            _logger.LogDebug("Deleted cache key: {Key} (Redis key: {RedisKey})", key, $"{_keyPrefix}{key}");
                        }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "Failed to delete cache key: {Key}", key);
                        }
                    }
                }

                // Delete comment count cache
                var countKey = $"comment_count:post:{postId}";
                try
                {
                    await _cache.RemoveAsync(countKey);
                    deletedCount++;
                    _logger.LogDebug("Deleted comment count cache key: {Key}", countKey);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to delete comment count cache key: {Key}", countKey);
                }

                // ALSO try direct Redis deletion with full keys (as backup)
                await InvalidateCachePattern($"comments:post:{postId}:*");

                _logger.LogInformation("Cache invalidation completed for post {PostId} - attempted to delete {Count} keys", postId, deletedCount);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to invalidate post comments cache for post {PostId}", postId);
            }
        }

        private async Task InvalidateUserCommentsCache(string userId)
        {
            try
            {
                // Pattern-based cache invalidation using Redis
                await InvalidateCachePattern($"comments:user:{userId}:*");

                _logger.LogDebug("Invalidated user comments cache for user {UserId}", userId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to invalidate user comments cache for user {UserId}", userId);
            }
        }

        private async Task InvalidateCachePattern(string pattern)
        {
            try
            {
                _logger.LogDebug("Starting pattern invalidation for: {Pattern} with prefix: '{Prefix}'", pattern, _keyPrefix);

                // Get all Redis servers
                var endpoints = _redis.GetEndPoints();
                _logger.LogDebug("Found {EndpointCount} Redis endpoints", endpoints.Length);

                var totalKeysDeleted = 0;

                foreach (var endpoint in endpoints)
                {
                    var server = _redis.GetServer(endpoint);
                    if (server == null || !server.IsConnected)
                    {
                        _logger.LogWarning("Redis server {Endpoint} is not connected", endpoint);
                        continue;
                    }

                    // Build the full pattern WITH the correct prefix
                    var fullPattern = $"{_keyPrefix}{pattern}";
                    _logger.LogInformation("Searching for Redis keys with pattern: '{FullPattern}'", fullPattern);

                    // Use SCAN to find matching keys
                    var keys = server.KeysAsync(pattern: fullPattern, pageSize: 1000);

                    var keysToDelete = new List<RedisKey>();
                    await foreach (var key in keys)
                    {
                        keysToDelete.Add(key);
                        _logger.LogInformation("Found key to delete: '{Key}'", key);

                        // Delete in batches of 100
                        if (keysToDelete.Count >= 100)
                        {
                            var deleted = await _database.KeyDeleteAsync(keysToDelete.ToArray());
                            totalKeysDeleted += (int)deleted;
                            _logger.LogInformation("Deleted batch of {Count} keys", deleted);
                            keysToDelete.Clear();
                        }
                    }

                    // Delete remaining keys
                    if (keysToDelete.Count > 0)
                    {
                        var deleted = await _database.KeyDeleteAsync(keysToDelete.ToArray());
                        totalKeysDeleted += (int)deleted;
                        _logger.LogInformation("Deleted final batch of {Count} keys", deleted);
                    }
                }

                _logger.LogInformation("Pattern invalidation complete - deleted {KeyCount} keys for pattern {Pattern}", totalKeysDeleted, pattern);

            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to invalidate cache pattern {Pattern}", pattern);
            }
        }

        private async Task DebugRedisKeys()
        {
            try
            {
                var endpoints = _redis.GetEndPoints();
                foreach (var endpoint in endpoints)
                {
                    var server = _redis.GetServer(endpoint);
                    if (server == null || !server.IsConnected) continue;

                    _logger.LogInformation("=== DEBUGGING REDIS KEYS ===");

                    // Get all keys (limit to first 50 for debugging)
                    var allKeys = server.KeysAsync(pattern: "*", pageSize: 50);
                    var keyCount = 0;
                    await foreach (var key in allKeys)
                    {
                        _logger.LogInformation("Redis key found: '{Key}'", key);
                        keyCount++;
                        if (keyCount >= 20) break; // Limit output
                    }

                    if (keyCount == 0)
                    {
                        _logger.LogWarning("No keys found in Redis at all!");
                    }

                    _logger.LogInformation("=== END REDIS DEBUG (showed {Count} keys) ===", keyCount);
                    break; // Only check first endpoint
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to debug Redis keys");
            }
        }

        private async Task FallbackCacheInvalidation(string pattern)
        {
            try
            {
                // Common page and size combinations to try
                var pageSizes = new[] { 10, 20, 25, 50, 100 };
                var pages = Enumerable.Range(1, 10); // First 10 pages

                if (pattern.Contains("comments:post:"))
                {
                    var postId = ExtractPostIdFromPattern(pattern);
                    foreach (var pageSize in pageSizes)
                    {
                        foreach (var page in pages)
                        {
                            var specificKey = $"comments:post:{postId}:page:{page}:size:{pageSize}";
                            await _cache.RemoveAsync(specificKey);
                        }
                    }
                }
                else if (pattern.Contains("comments:user:"))
                {
                    var userId = ExtractUserIdFromPattern(pattern);
                    foreach (var pageSize in pageSizes)
                    {
                        foreach (var page in pages)
                        {
                            var specificKey = $"comments:user:{userId}:page:{page}:size:{pageSize}";
                            await _cache.RemoveAsync(specificKey);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Fallback cache invalidation failed for pattern {Pattern}", pattern);
            }
        }

        private string ExtractPostIdFromPattern(string pattern)
        {
            // Extract postId from pattern like "comments:post:123:*"
            var parts = pattern.Split(':');
            return parts.Length >= 3 ? parts[2] : "";
        }

        private string ExtractUserIdFromPattern(string pattern)
        {
            // Extract userId from pattern like "comments:user:userId123:*"
            var parts = pattern.Split(':');
            return parts.Length >= 3 ? parts[2] : "";
        }
    }

    public class CommentPageResult
    {
        public IEnumerable<Comment> Comments { get; set; } = new List<Comment>();
        public int TotalCount { get; set; }
    }
}