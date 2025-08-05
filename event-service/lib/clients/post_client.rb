require 'grpc'
require 'concurrent'
require 'securerandom'
require_relative '../grpc/postpb/post_services_pb'

module EventService
  module GrpcClients
    class PostClient < BaseClient
      def initialize(host = nil, port = nil, logger = nil)
        host ||= EventService.configuration.post_service_host || 'post-service'
        port ||= EventService.configuration.post_service_port || 50051
        super(host, port, logger)
      end

      def create_post(user_id:, title:, slug:, desc:, category:, content:, img: nil, is_featured: false)
        return nil if user_id.nil? || user_id.empty? || title.nil? || title.empty?

        request = PostPb::CreatePostRequest.new(
          user_id: user_id,
          img: img,
          title: title,
          slug: slug,
          desc: desc,
          category: category,
          content: content,
          is_featured: is_featured
        )

        begin
          response = @stub.create_post(request, call_options)
          logger.debug("Created post: #{response.post.id}")
          response.post if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "CreatePost")
          nil
        rescue StandardError => e
          logger.error("Unexpected error creating post: #{e.message}")
          nil
        end
      end

      def get_post(post_id)
        return nil if post_id.nil? || post_id == 0

        request = PostPb::GetPostRequest.new(id: post_id)
        
        begin
          response = @stub.get_post(request, call_options)
          logger.debug("Retrieved post: #{post_id}")
          response.post if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetPost")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting post #{post_id}: #{e.message}")
          nil
        end
      end

      def get_post_by_slug(slug)
        return nil if slug.nil? || slug.empty?

        request = PostPb::GetPostBySlugRequest.new(slug: slug)
        
        begin
          response = @stub.get_post_by_slug(request, call_options)
          logger.debug("Retrieved post by slug: #{slug}")
          response.post if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetPostBySlug")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting post by slug #{slug}: #{e.message}")
          nil
        end
      end

      def update_post(id:, user_id: nil, img: nil, title: nil, slug: nil, desc: nil, category: nil, content: nil, is_featured: nil)
        return nil if id.nil? || id == 0

        request = PostPb::UpdatePostRequest.new(
          id: id,
          user_id: user_id,
          img: img,
          title: title,
          slug: slug,
          desc: desc,
          category: category,
          content: content,
          is_featured: is_featured
        )

        begin
          response = @stub.update_post(request, call_options)
          logger.debug("Updated post: #{id}")
          response.post if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UpdatePost")
          nil
        rescue StandardError => e
          logger.error("Unexpected error updating post #{id}: #{e.message}")
          nil
        end
      end

      def delete_post(post_id, user_id = nil)
        return false if post_id.nil? || post_id == 0

        request = PostPb::DeletePostRequest.new(
          id: post_id,
          user_id: user_id
        )

        begin
          response = @stub.delete_post(request, call_options)
          logger.debug("Deleted post: #{post_id}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeletePost")
          false
        rescue StandardError => e
          logger.error("Unexpected error deleting post #{post_id}: #{e.message}")
          false
        end
      end

      def delete_posts(post_ids, user_ids = [])
        return false if post_ids.nil? || post_ids.empty?

        request = PostPb::DeletePostsRequest.new(
          ids: post_ids,
          user_ids: user_ids
        )

        begin
          response = @stub.delete_posts(request, call_options)
          logger.debug("Deleted #{post_ids.size} posts")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeletePosts")
          false
        rescue StandardError => e
          logger.error("Unexpected error deleting posts: #{e.message}")
          false
        end
      end

      def list_posts(page: 1, limit: 10, category: nil, user_id: nil)
        request = PostPb::ListPostsRequest.new(
          page: page,
          limit: limit,
          category: category,
          user_id: user_id
        )
        
        begin
          response = @stub.list_posts(request, call_options)
          logger.debug("Listed #{response.posts.size} posts (page: #{page}, total: #{response.total})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "ListPosts")
          nil
        rescue StandardError => e
          logger.error("Unexpected error listing posts: #{e.message}")
          nil
        end
      end

      def get_posts_by_user(user_id, page: 1, limit: 10)
        return [] if user_id.nil? || user_id.empty?

        request = PostPb::GetPostsByUserRequest.new(
          user_id: user_id,
          page: page,
          limit: limit
        )
        
        begin
          response = @stub.get_posts_by_user(request, call_options)
          logger.debug("Retrieved #{response.posts.size} posts for user: #{user_id}")
          response.posts
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetPostsByUser")
          []
        rescue StandardError => e
          logger.error("Unexpected error getting posts for user #{user_id}: #{e.message}")
          []
        end
      end

      def get_posts_by_category(category, page: 1, limit: 10)
        return [] if category.nil? || category.empty?

        request = PostPb::GetPostsByCategoryRequest.new(
          category: category,
          page: page,
          limit: limit
        )
        
        begin
          response = @stub.get_posts_by_category(request, call_options)
          logger.debug("Retrieved #{response.posts.size} posts for category: #{category}")
          response.posts
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetPostsByCategory")
          []
        rescue StandardError => e
          logger.error("Unexpected error getting posts for category #{category}: #{e.message}")
          []
        end
      end

      def get_featured_posts(limit: 10)
        request = PostPb::GetFeaturedPostsRequest.new(limit: limit)
        
        begin
          response = @stub.get_featured_posts(request, call_options)
          logger.debug("Retrieved #{response.posts.size} featured posts")
          response.posts
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetFeaturedPosts")
          []
        rescue StandardError => e
          logger.error("Unexpected error getting featured posts: #{e.message}")
          []
        end
      end

      def search_posts(query, page: 1, limit: 10)
        return [] if query.nil? || query.empty?

        request = PostPb::SearchPostsRequest.new(
          query: query,
          page: page,
          limit: limit
        )
        
        begin
          response = @stub.search_posts(request, call_options)
          logger.debug("Found #{response.posts.size} posts for query: #{query}")
          response.posts
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "SearchPosts")
          []
        rescue StandardError => e
          logger.error("Unexpected error searching posts for query #{query}: #{e.message}")
          []
        end
      end

      def increment_visit(post_id)
        return nil if post_id.nil? || post_id == 0

        request = PostPb::IncrementVisitRequest.new(id: post_id)

        begin
          response = @stub.increment_visit(request, call_options)
          logger.debug("Incremented visit count for post: #{post_id}")
          response.post if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "IncrementVisit")
          nil
        rescue StandardError => e
          logger.error("Unexpected error incrementing visit for post #{post_id}: #{e.message}")
          nil
        end
      end

      def count_posts(user_id: nil, category: nil, is_featured: nil)
        request = PostPb::CountPostsRequest.new(
          user_id: user_id,
          category: category,
          is_featured: is_featured
        )

        begin
          response = @stub.count_posts(request, call_options)
          logger.debug("Retrieved post count: #{response.total}")
          response.total
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "CountPosts")
          0
        rescue StandardError => e
          logger.error("Unexpected error counting posts: #{e.message}")
          0
        end
      end

      private

      def create_stub
        PostPb::PostService::Stub.new("#{@host}:#{@port}", 
                                      :this_channel_is_insecure, 
                                      channel_args: channel_args)
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