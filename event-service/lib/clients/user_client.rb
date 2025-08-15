require 'grpc'
require 'concurrent'
require 'securerandom'
require_relative '../grpc/userpb/user_services_pb'

module EventService
  module GrpcClients
    class UserClient < BaseClient
      def initialize(host = nil, port = nil, logger = nil)
        host ||= EventService.configuration.services[:user][:host] || 'user-service'
        port ||= EventService.configuration.services[:user][:port] || 50051
        super(host, port, logger)
      end

      def list_users(limit: 50, offset: 0, email_addresses: [], usernames: [], user_ids: [])
        request = User::ListUsersRequest.new(
          limit: limit,
          offset: offset,
          email_address: email_addresses,
          username: usernames,
          user_id: user_ids
        )

        begin
          response = @stub.list_users(request, call_options)
          logger.debug("Listed #{response.users.size} users (total: #{response.total_count})")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "ListUsers")
          nil
        rescue StandardError => e
          logger.error("Unexpected error listing users: #{e.message}")
          nil
        end
      end

      def get_user(user_id)
        return nil if user_id.nil? || user_id.empty?

        request = User::GetUserRequest.new(user_id: user_id)
        
        begin
          response = @stub.get_user(request, call_options)
          logger.debug("Retrieved user: #{user_id}")
          response.user
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting user #{user_id}: #{e.message}")
          nil
        end
      end

      def get_local_user(user_id)
        return nil if user_id.nil? || user_id.empty?

        request = User::GetUserRequest.new(user_id: user_id)
        
        begin
          response = @stub.get_local_user(request, call_options)
          logger.debug("Retrieved user: #{user_id}")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting user #{user_id}: #{e.message}")
          nil
        end
      end

      def create_user(email:, password:, username: nil, first_name: nil, last_name: nil, role: nil)
        return nil if email.nil? || email.empty? || password.nil? || password.empty?

        request = User::CreateUserRequest.new(
          email: email,
          password: password,
          username: username,
          first_name: first_name,
          last_name: last_name,
          role: role
        )

        begin
          response = @stub.create_user(request, call_options)
          logger.debug("Created user: #{response.user.id}")
          response.user
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "CreateUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error creating user: #{e.message}")
          nil
        end
      end

      def update_user(user_id:, username: nil, first_name: nil, last_name: nil, role: nil)
        return nil if user_id.nil? || user_id.empty?

        request = User::UpdateUserRequest.new(
          user_id: user_id,
          username: username,
          first_name: first_name,
          last_name: last_name,
          role: role
        )

        begin
          response = @stub.update_user(request, call_options)
          logger.debug("Updated user: #{user_id}")
          response.user
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UpdateUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error updating user #{user_id}: #{e.message}")
          nil
        end
      end

      def delete_user(user_id)
        return nil if user_id.nil? || user_id.empty?

        request = User::DeleteUserRequest.new(user_id: user_id)

        begin
          response = @stub.delete_user(request, call_options)
          logger.debug("Deleted user: #{user_id}")
          response.user
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeleteUser")
          nil
        rescue StandardError => e
          logger.error("Unexpected error deleting user #{user_id}: #{e.message}")
          nil
        end
      end

      def get_user_count(email_addresses: [], usernames: [], user_ids: [])
        request = User::UserFilterRequest.new(
          email_address: email_addresses,
          username: usernames,
          user_id: user_ids
        )

        begin
          response = @stub.get_user_count(request, call_options)
          logger.debug("Retrieved user count: #{response.count}")
          response.count
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetUserCount")
          0
        rescue StandardError => e
          logger.error("Unexpected error getting user count: #{e.message}")
          0
        end
      end

      def update_user_role(user_id, role)
        return nil if user_id.nil? || user_id.empty? || role.nil? || role.empty?

        request = User::UpdateUserRoleRequest.new(
          user_id: user_id,
          role: role
        )

        begin
          response = @stub.update_user_role(request, call_options)
          logger.debug("Updated role for user: #{user_id} to #{role}")
          response.user
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UpdateUserRole")
          nil
        rescue StandardError => e
          logger.error("Unexpected error updating user role #{user_id}: #{e.message}")
          nil
        end
      end

      def get_oauth_access_token(user_id, provider)
        return nil if user_id.nil? || user_id.empty? || provider.nil? || provider.empty?

        request = User::OAuthTokenRequest.new(
          user_id: user_id,
          provider: provider
        )

        begin
          response = @stub.get_o_auth_access_token(request, call_options)
          logger.debug("Retrieved OAuth tokens for user: #{user_id}, provider: #{provider}")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetOAuthAccessToken")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting OAuth token for user #{user_id}: #{e.message}")
          nil
        end
      end

      private

      def create_stub
        User::UserService::Stub.new("#{@host}:#{@port}", :this_channel_is_insecure)
        # User::UserService::Service.new
                                      
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