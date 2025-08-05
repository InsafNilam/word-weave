require 'singleton'
require 'connection_pool'

module EventService
  module GrpcClients
    class ClientPool
      include Singleton

      attr_reader :user_clients, :post_clients

      def initialize
        @user_clients = ConnectionPool.new(size: 5, timeout: 5) do
          UserClient.new
        end

        @post_clients = ConnectionPool.new(size: 5, timeout: 5) do
          PostClient.new
        end
      end

      def with_user_client(&block)
        @user_clients.with(&block)
      end

      def with_post_client(&block)
        @post_clients.with(&block)
      end

      def with_like_client(&block)
        @like_clients.with(&block)
      end

      def with_comment_client(&block)
        @comment_clients.with(&block)
      end

      def with_like_client(&block)
        @like_clients.with(&block)
      end
    end
  end
end