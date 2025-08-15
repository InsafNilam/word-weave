require 'grpc'
require 'concurrent'
require 'securerandom'
require_relative '../grpc/mediapb/media_services_pb'

module EventService
  module GrpcClients
    class MediaClient < BaseClient
      def initialize(host = nil, port = nil, logger = nil)
        host ||= EventService.configuration.services[:media][:host] || 'media-service'
        port ||= EventService.configuration.services[:media][:port] || 50056
        super(host, port, logger)
      end

      def get_upload_auth
        request = Media::GetUploadAuthRequest.new

        begin
          response = @stub.get_upload_auth(request, call_options)
          logger.debug("Retrieved upload auth token")
          response if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetUploadAuth")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting upload auth: #{e.message}")
          nil
        end
      end

      def get_file_details(file_id)
        return nil if file_id.nil? || file_id.empty?

        request = Media::GetFileDetailsRequest.new(file_id: file_id)

        begin
          response = @stub.get_file_details(request, call_options)
          logger.debug("Retrieved file details for: #{file_id}")
          response.file if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetFileDetails")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting file details for #{file_id}: #{e.message}")
          nil
        end
      end

      def get_files(skip: 0, limit: 10, search_query: nil, tags: [], file_type: nil, sort: nil, path: nil)
        request = Media::GetFilesRequest.new(
          skip: skip,
          limit: limit,
          search_query: search_query,
          tags: tags || [],
          file_type: file_type,
          sort: sort,
          path: path
        )

        begin
          response = @stub.get_files(request, call_options)
          logger.debug("Retrieved #{response.files.size} files (skip: #{skip}, limit: #{limit}, total: #{response.total_count})")
          response if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "GetFiles")
          nil
        rescue StandardError => e
          logger.error("Unexpected error getting files: #{e.message}")
          nil
        end
      end

      def upload_file(file_data:, filename:, folder: nil, tags: [], use_unique_filename: true, custom_coordinates: nil)
        return nil if file_data.nil? || file_data.empty? || filename.nil? || filename.empty?

        request = Media::UploadFileRequest.new(
          file_data: file_data,
          filename: filename,
          folder: folder,
          tags: tags || [],
          use_unique_filename: use_unique_filename,
          custom_coordinates: custom_coordinates
        )

        begin
          response = @stub.upload_file(request, call_options)
          logger.debug("Uploaded file: #{filename} -> #{response.file&.file_id}")
          response.file if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UploadFile")
          nil
        rescue StandardError => e
          logger.error("Unexpected error uploading file #{filename}: #{e.message}")
          nil
        end
      end

      def update_file_details(file_id:, tags: nil, custom_coordinates: nil, custom_metadata: {})
        return nil if file_id.nil? || file_id.empty?

        request = Media::UpdateFileDetailsRequest.new(
          file_id: file_id,
          tags: tags || [],
          custom_coordinates: custom_coordinates,
          custom_metadata: custom_metadata || {}
        )

        begin
          response = @stub.update_file_details(request, call_options)
          logger.debug("Updated file details: #{file_id}")
          response.file if response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "UpdateFileDetails")
          nil
        rescue StandardError => e
          logger.error("Unexpected error updating file details for #{file_id}: #{e.message}")
          nil
        end
      end

      def delete_file(file_id)
        return false if file_id.nil? || file_id.empty?

        request = Media::DeleteFileRequest.new(file_id: file_id)

        begin
          response = @stub.delete_file(request, call_options)
          logger.debug("Deleted file: #{file_id}")
          response.success
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeleteFile")
          false
        rescue StandardError => e
          logger.error("Unexpected error deleting file #{file_id}: #{e.message}")
          false
        end
      end

      def delete_multiple_files(file_ids)
        return nil if file_ids.nil? || file_ids.empty?

        request = Media::DeleteMultipleFilesRequest.new(file_ids: file_ids)

        begin
          response = @stub.delete_multiple_files(request, call_options)
          logger.debug("Deleted #{file_ids.size} files - all success: #{response.all_success}")
          response
        rescue GRPC::BadStatus => e
          handle_grpc_error(e, "DeleteMultipleFiles")
          nil
        rescue StandardError => e
          logger.error("Unexpected error deleting multiple files: #{e.message}")
          nil
        end
      end

      # Convenience methods for easier usage
      def upload_file_from_path(file_path, folder: nil, tags: [], use_unique_filename: true, custom_coordinates: nil)
        return nil unless File.exist?(file_path)

        file_data = File.binread(file_path)
        filename = File.basename(file_path)

        upload_file(
          file_data: file_data,
          filename: filename,
          folder: folder,
          tags: tags,
          use_unique_filename: use_unique_filename,
          custom_coordinates: custom_coordinates
        )
      rescue StandardError => e
        logger.error("Error reading file #{file_path}: #{e.message}")
        nil
      end

      def search_files(query, skip: 0, limit: 10, file_type: nil)
        get_files(
          skip: skip,
          limit: limit,
          search_query: query,
          file_type: file_type
        )
      end

      def get_files_by_tags(tags, skip: 0, limit: 10)
        get_files(
          skip: skip,
          limit: limit,
          tags: tags
        )
      end

      def get_files_by_type(file_type, skip: 0, limit: 10)
        get_files(
          skip: skip,
          limit: limit,
          file_type: file_type
        )
      end

      def get_files_in_folder(path, skip: 0, limit: 10)
        get_files(
          skip: skip,
          limit: limit,
          path: path
        )
      end

      def add_tags_to_file(file_id, new_tags)
        file = get_file_details(file_id)
        return nil unless file

        existing_tags = file.tags.to_a
        combined_tags = (existing_tags + new_tags).uniq

        update_file_details(
          file_id: file_id,
          tags: combined_tags,
          custom_coordinates: file.custom_coordinates,
          custom_metadata: file.custom_metadata.to_h
        )
      end

      def remove_tags_from_file(file_id, tags_to_remove)
        file = get_file_details(file_id)
        return nil unless file

        remaining_tags = file.tags.to_a - tags_to_remove

        update_file_details(
          file_id: file_id,
          tags: remaining_tags,
          custom_coordinates: file.custom_coordinates,
          custom_metadata: file.custom_metadata.to_h
        )
      end

      def bulk_delete_successful?(delete_response)
        return false unless delete_response
        delete_response.all_success
      end

      def get_failed_deletions(delete_response)
        return [] unless delete_response&.results

        delete_response.results.select { |result| !result.success }
      end

      def get_successful_deletions(delete_response)
        return [] unless delete_response&.results

        delete_response.results.select(&:success)
      end

      private

      def create_stub
        Media::MediaService::Stub.new("#{@host}:#{@port}", :this_channel_is_insecure)
        # Media::MediaService::Service.new
      end

      def channel_args
        {
          'grpc.keepalive_time_ms' => 30000,
          'grpc.keepalive_timeout_ms' => 5000,
          'grpc.keepalive_permit_without_calls' => true,
          'grpc.http2.max_pings_without_data' => 0,
          'grpc.http2.min_time_between_pings_ms' => 10000,
          'grpc.http2.min_ping_interval_without_data_ms' => 300000,
          'grpc.max_receive_message_length' => 100 * 1024 * 1024, # 100MB for file uploads
          'grpc.max_send_message_length' => 100 * 1024 * 1024     # 100MB for file uploads
        }
      end
    end
  end
end