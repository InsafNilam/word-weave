using CommentService.ExternalGrpc;
using Grpc.Core;
using Grpc.Net.Client;
using Microsoft.Extensions.Caching.Distributed;
using System.Text.Json;

namespace CommentService.Services
{
    public interface IExternalServices
    {
        Task<bool> ValidateUserAsync(string userId);
        Task<bool> ValidatePostAsync(uint postId);
        Task<User?> GetUserAsync(string userId);
        Task<Post?> GetPostAsync(uint postId);
        Task<Event?> PublishEvent(
            string aggregate_id,
            string aggregate_type,
            string event_type,
            string event_data,
            string metadata,
            string correlation_id,
            string causation_id
        );
    }

    public class ExternalServices : IExternalServices
    {
        private readonly UserService.UserServiceClient _userServiceClient;
        private readonly PostService.PostServiceClient _postServiceClient;
        private readonly EventService.EventServiceClient _eventServiceClient;
        private readonly IDistributedCache _cache;
        private readonly ILogger<ExternalServices> _logger;
        private readonly TimeSpan _cacheDuration = TimeSpan.FromMinutes(10);

        public ExternalServices(
            IConfiguration configuration,
            IDistributedCache cache,
            ILogger<ExternalServices> logger)
        {
            _cache = cache;
            _logger = logger;

            // Initialize gRPC clients
            var userServiceUrl = configuration["GrpcSettings:UserServiceUrl"];
            var postServiceUrl = configuration["GrpcSettings:PostServiceUrl"];
            var eventServiceUrl = configuration["GrpcSettings:EventServiceUrl"];

            var userChannel = GrpcChannel.ForAddress(userServiceUrl!);
            var postChannel = GrpcChannel.ForAddress(postServiceUrl!);
            var eventChannel = GrpcChannel.ForAddress(eventServiceUrl!);

            _userServiceClient = new UserService.UserServiceClient(userChannel);
            _postServiceClient = new PostService.PostServiceClient(postChannel);
            _eventServiceClient = new EventService.EventServiceClient(eventChannel);
        }

        public async Task<bool> ValidateUserAsync(string userId)
        {
            var cacheKey = $"user_validation:{userId}";

            try
            {
                var cachedResult = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedResult))
                {
                    _logger.LogDebug("Cache hit for user validation {UserId}", userId);
                    return JsonSerializer.Deserialize<bool>(cachedResult);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get user validation from cache for user {UserId}", userId);
            }

            try
            {
                var request = new GetUserRequest { UserId = userId };
                var response = await _userServiceClient.GetUserAsync(request, deadline: DateTime.UtcNow.AddSeconds(5));

                var isValid = response.Success;
                await SetCacheAsync(cacheKey, isValid);

                _logger.LogDebug("User validation for {UserId}: {IsValid}", userId, isValid);
                return isValid;
            }
            catch (RpcException ex)
            {
                _logger.LogError(ex, "gRPC error validating user {UserId}: {StatusCode}", userId, ex.StatusCode);
                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating user {UserId}", userId);
                return false;
            }
        }

        public async Task<bool> ValidatePostAsync(uint postId)
        {
            var cacheKey = $"post_validation:{postId}";

            try
            {
                var cachedResult = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedResult))
                {
                    _logger.LogDebug("Cache hit for post validation {PostId}", postId);
                    return JsonSerializer.Deserialize<bool>(cachedResult);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get post validation from cache for post {PostId}", postId);
            }

            try
            {
                var request = new GetPostRequest { PostId = postId };
                var response = await _postServiceClient.GetPostAsync(request, deadline: DateTime.UtcNow.AddSeconds(5));

                var isValid = response.Success;
                await SetCacheAsync(cacheKey, isValid);

                _logger.LogDebug("Post validation for {PostId}: {IsValid}", postId, isValid);
                return isValid;
            }
            catch (RpcException ex)
            {
                _logger.LogError(ex, "gRPC error validating post {PostId}: {StatusCode}", postId, ex.StatusCode);
                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating post {PostId}", postId);
                return false;
            }
        }

        public async Task<User?> GetUserAsync(string userId)
        {
            var cacheKey = $"user_data:{userId}";

            try
            {
                var cachedUser = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedUser))
                {
                    _logger.LogDebug("Cache hit for user data {UserId}", userId);
                    return JsonSerializer.Deserialize<User>(cachedUser);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get user data from cache for user {UserId}", userId);
            }

            try
            {
                var request = new GetUserRequest { UserId = userId };
                var response = await _userServiceClient.GetUserAsync(request, deadline: DateTime.UtcNow.AddSeconds(5));

                if (response.Success && response.User != null)
                {
                    await SetCacheAsync(cacheKey, response.User);
                    return response.User;
                }

                _logger.LogWarning("Failed to get user {UserId}: {Message}", userId, response.Message);
                return null;
            }
            catch (RpcException ex)
            {
                _logger.LogError(ex, "gRPC error getting user {UserId}: {StatusCode}", userId, ex.StatusCode);
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting user {UserId}", userId);
                return null;
            }
        }

        public async Task<Post?> GetPostAsync(uint postId)
        {
            var cacheKey = $"post_data:{postId}";

            try
            {
                var cachedPost = await _cache.GetStringAsync(cacheKey);
                if (!string.IsNullOrEmpty(cachedPost))
                {
                    _logger.LogDebug("Cache hit for post data {PostId}", postId);
                    return JsonSerializer.Deserialize<Post>(cachedPost);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get post data from cache for post {PostId}", postId);
            }

            try
            {
                var request = new GetPostRequest { PostId = postId };
                var response = await _postServiceClient.GetPostAsync(request, deadline: DateTime.UtcNow.AddSeconds(5));

                if (response.Success && response.Post != null)
                {
                    await SetCacheAsync(cacheKey, response.Post);
                    return response.Post;
                }

                _logger.LogWarning("Failed to get post {PostId}: {Message}", postId, response.Message);
                return null;
            }
            catch (RpcException ex)
            {
                _logger.LogError(ex, "gRPC error getting post {PostId}: {StatusCode}", postId, ex.StatusCode);
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting post {PostId}", postId);
                return null;
            }
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

        public async Task<Event?> PublishEvent(
            string aggregate_id,
            string aggregate_type,
            string event_type,
            string event_data,
            string metadata,
            string correlation_id,
            string causation_id)
        {
            try
            {
                var request = new PublishEventRequest
                {
                    AggregateId = aggregate_id,
                    AggregateType = aggregate_type,
                    EventType = event_type,
                    EventData = event_data,
                    Metadata = metadata,
                    CorrelationId = correlation_id,
                    CausationId = causation_id
                };

                var response = await _eventServiceClient.PublishEventAsync(request, deadline: DateTime.UtcNow.AddSeconds(5));

                if (response.Success && response.EventId != null)
                {
                    return new Event
                    {
                        Id = response.EventId,
                        AggregateId = aggregate_id,
                        AggregateType = aggregate_type,
                        EventType = event_type,
                        EventData = event_data,
                        Metadata = metadata,
                        CorrelationId = correlation_id,
                        CausationId = causation_id,
                    };
                }

                _logger.LogWarning("Failed to publish event: {Message}", response.Message);
                return null;
            }
            catch (RpcException ex)
            {
                _logger.LogError(ex, "gRPC error publishing event: {StatusCode}", ex.StatusCode);
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error publishing event");
                return null;
            }
        }
    }
}