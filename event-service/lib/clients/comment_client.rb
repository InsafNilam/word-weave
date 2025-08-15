require 'grpc'
require 'concurrent'
require 'securerandom'
require_relative '../grpc/commentpb/comment_services_pb'

module EventService
  module GrpcClients
    class CommentClient < BaseClient
      def initialize(host = nil, port = nil, logger = nil)
        host ||= EventService.configuration.services[:comment][:host] || 'comment-service'
        port ||= EventService.configuration.services[:comment][:post] || 50054
        super(host, port, logger)
      end

      def create_comment(user_id:, post_id:, description:)
        return nil if user_id.nil? || user_id.empty? || post_id.nil? || post_id == 0 || description.nil? || description.empty?

        request = Comment::CreateCommentRequest.new(
          user_id: user_id,
          post_id: post_id,
          description: description
        )

        begin
          response = @stub.create_comment(request, call_options)
          logger.debug("Created comment: #{response.comment.id}")
          response.comment if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "CreateComment")
          nil
        rescue StandardError => e
          logger.error("Unexpected error creating comment: #{e.message}")
          nil
        end
      end

      def get_comment(comment_id)
        return nil if comment_id.nil? || comment_id == 0

        request = Comment::GetCommentRequest.new(id: comment_id)
        
        begin
          response = @stub.get_comment(request, call_options)
          logger.debug("Retrieved comment: #{comment_id}")
          response.comment if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetComment")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting comment #{comment_id}: #{e.message}")
          nil
        end
      end

      def get_comments_by_post(post_id, page: 1, page_size: 10)
        return nil if post_id.nil? || post_id == 0

        request = Comment::GetCommentsByPostRequest.new(
          post_id: post_id,
          page: page,
          page_size: page_size
        )
        
        begin
          response = @stub.get_comments_by_post(request, call_options)
          logger.debug("Retrieved #{response.comments.size} comments for post: #{post_id} (page: #{page}, total: #{response.total_count})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetCommentsByPost")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting comments for post #{post_id}: #{e.message}")
          nil
        end
      end

      def get_comments_by_user(user_id, page: 1, page_size: 10)
        return nil if user_id.nil? || user_id.empty?

        request = Comment::GetCommentsByUserRequest.new(
          user_id: user_id,
          page: page,
          page_size: page_size
        )
        
        begin
          response = @stub.get_comments_by_user(request, call_options)
          logger.debug("Retrieved #{response.comments.size} comments for user: #{user_id} (page: #{page}, total: #{response.total_count})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetCommentsByUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting comments for user #{user_id}: #{e.message}")
          nil
        end
      end

      def update_comment(id:, user_id:, description:)
        return nil if id.nil? || id == 0 || user_id.nil? || user_id.empty? || description.nil? || description.empty?

        request = Comment::UpdateCommentRequest.new(
          id: id,
          user_id: user_id,
          description: description
        )

        begin
          response = @stub.update_comment(request, call_options)
          logger.debug("Updated comment: #{id}")
          response.comment if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UpdateComment")
          nil
        rescue StandardError => e
          logger.error("Unexpected error updating comment #{id}: #{e.message}")
          nil
        end
      end

      def delete_comment(comment_id, user_id, post_id)
        return false if comment_id.nil? || comment_id == 0

        request = Comment::DeleteCommentRequest.new(
          id: comment_id,
          user_id: user_id,
          post_id: post_id
        )

        begin
          response = @stub.delete_comment(request, call_options)
          logger.debug("Deleted comment: #{comment_id}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeleteComment")
          false
        rescue StandardError => e
          logger.error("Unexpected error deleting comment #{comment_id}: #{e.message}")
          false
        end
      end

      def delete_comments(user_ids, post_ids)
        return false if (user_ids.nil? || user_ids.empty?) && (post_ids.nil? || post_ids.empty?)

        request = Comment::DeleteCommentsRequest.new(
          user_ids: user_ids || [],
          post_ids: post_ids || []
        )

        begin
          response = @stub.delete_comments(request, call_options)
          logger.debug("Deleted #{user_ids.size} comments for users: #{user_ids.join(", ")} on posts: #{post_ids.join(", ")}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeleteComments")
          false
        rescue StandardError => e
          logger.error("Unexpected error deleting comments: #{e.message}")
          false
        end
      end

      def get_comment_count(post_id)
        return 0 if post_id.nil? || post_id == 0

        request = Comment::GetCommentCountRequest.new(post_id: post_id)

        begin
          response = @stub.get_comment_count(request, call_options)
          logger.debug("Retrieved comment count for post #{post_id}: #{response.count}")
          response.count
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetCommentCount")
          0
        rescue StandardError => e
          logger.error("Unexpected error getting comment count for post #{post_id}: #{e.message}")
          0
        end
      end

      private

      def create_stub
        Comment::CommentService::Stub.new("#{@host}:#{@port}", :this_channel_is_insecure)
        # Comment::CommentService::Service.new
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