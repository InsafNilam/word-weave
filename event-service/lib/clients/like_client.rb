require 'grpc'
require 'concurrent'
require 'securerandom'
require_relative '../grpc/likepb/like_services_pb'

module EventService
  module GrpcClients
    class LikeClient < BaseClient
      def initialize(host = nil, port = nil, logger = nil)
        host ||= EventService.configuration.services[:like][:host] || 'like-service'
        port ||= EventService.configuration.services[:like][:port] || 50053
        super(host, port, logger)
      end

      def like_post(user_id:, post_id:)
        return nil if user_id.nil? || user_id.empty? || post_id.nil? || post_id.empty?

        request = Like::LikePostRequest.new(
          user_id: user_id,
          post_id: post_id
        )

        begin
          response = @stub.like_post(request, call_options)
          logger.debug("User #{user_id} liked post #{post_id}")
          response if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "LikePost")
          nil
        rescue StandardError => e
          logger.error("Unexpected error liking post #{post_id} for user #{user_id}: #{e.message}")
          nil
        end
      end

      def unlike_post(user_id:, post_id:)
        return nil if user_id.nil? || user_id.empty? || post_id.nil? || post_id.empty?

        request = Like::UnlikePostRequest.new(
          user_id: user_id,
          post_id: post_id
        )

        begin
          response = @stub.unlike_post(request, call_options)
          logger.debug("User #{user_id} unliked post #{post_id}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UnlikePost")
          false
        rescue StandardError => e
          logger.error("Unexpected error unliking post #{post_id} for user #{user_id}: #{e.message}")
          false
        end
      end

      def unlike_posts(user_ids: [], post_ids: [])
        return false if (user_ids.nil? || user_ids.empty?) && (post_ids.nil? || post_ids.empty?)

        request = Like::UnlikePostsRequest.new(
          user_ids: user_ids || [],
          post_ids: post_ids || []
        )

        begin
          response = @stub.unlike_posts(request, call_options)
          logger.debug("Bulk unliked posts - users: #{user_ids.size}, posts: #{post_ids.size}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UnlikePosts")
          false
        rescue StandardError => e
          logger.error("Unexpected error bulk unliking posts: #{e.message}")
          false
        end
      end

      def get_user_likes(user_id, page: 1, limit: 10)
        return nil if user_id.nil? || user_id.empty?

        request = Like::GetUserLikesRequest.new(
          user_id: user_id,
          page: page,
          limit: limit
        )

        begin
          response = @stub.get_user_likes(request, call_options)
          logger.debug("Retrieved #{response.likes.size} likes for user: #{user_id} (page: #{page})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetUserLikes")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting likes for user #{user_id}: #{e.message}")
          nil
        end
      end

      def get_post_likes(post_id, page: 1, limit: 10)
        return nil if post_id.nil? || post_id.empty?

        request = Like::GetPostLikesRequest.new(
          post_id: post_id,
          page: page,
          limit: limit
        )

        begin
          response = @stub.get_post_likes(request, call_options)
          logger.debug("Retrieved #{response.likes.size} likes for post: #{post_id} (page: #{page})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetPostLikes")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting likes for post #{post_id}: #{e.message}")
          nil
        end
      end

      def is_post_liked?(user_id:, post_id:)
        return false if user_id.nil? || user_id.empty? || post_id.nil? || post_id.empty?

        request = Like::IsPostLikedRequest.new(
          user_id: user_id,
          post_id: post_id
        )

        begin
          response = @stub.is_post_liked(request, call_options)
          logger.debug("Checked if user #{user_id} liked post #{post_id}: #{response.is_liked}")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "IsPostLiked")
          nil
        rescue StandardError => e
          logger.error("Unexpected error checking if post #{post_id} is liked by user #{user_id}: #{e.message}")
          nil
        end
      end

      def get_likes_count(post_id)
        return 0 if post_id.nil? || post_id.empty?

        request = Like::GetLikesCountRequest.new(post_id: post_id)

        begin
          response = @stub.get_likes_count(request, call_options)
          logger.debug("Retrieved likes count for post #{post_id}: #{response.count}")
          response.count
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetLikesCount")
          0
        rescue StandardError => e
          logger.error("Unexpected error getting likes count for post #{post_id}: #{e.message}")
          0
        end
      end

      def health_check
        request = Like::HealthCheckRequest.new

        begin
          response = @stub.health_check(request, call_options)
          logger.debug("Health check successful: #{response.status}")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "HealthCheck")
          nil
        rescue StandardError => e
          logger.error("Unexpected error during health check: #{e.message}")
          nil
        end
      end

      # Convenience methods for easier usage
      def toggle_like(user_id:, post_id:)
        return nil if user_id.nil? || user_id.empty? || post_id.nil? || post_id.empty?

        liked_response = is_post_liked?(user_id: user_id, post_id: post_id)
        return nil unless liked_response

        if liked_response.is_liked
          unlike_post(user_id: user_id, post_id: post_id)
        else
          like_post(user_id: user_id, post_id: post_id)
        end
      end

      def get_user_liked_posts(user_id, page: 1, limit: 10)
        response = get_user_likes(user_id, page: page, limit: limit)
        return [] unless response

        response.likes.map(&:post_id)
      end

      def get_post_likers(post_id, page: 1, limit: 10)
        response = get_post_likes(post_id, page: page, limit: limit)
        return [] unless response

        response.likes.map(&:user_id)
      end

      private

      def create_stub
        Like::LikesService::Stub.new("#{@host}:#{@port}", :this_channel_is_insecure)
        # Like::LikesService::Service.new
      end

      def channel_args
        {
          'grpc.keepalive_time_ms' => 30000,
          'grpc.keepalive_timeout_ms' => 5000,
          'grpc.keepalive_permit_without_calls' => true,
          'grpc.http2.max_pings_without_data' => 0,
          'grpc.http2.min_time_between_pings_ms' => 10000,
          'grpc.http2.min_ping_interval_without_data_ms' => 300000
        }
      end
    end
  end
end