require 'grpc'
require 'concurrent'
require 'securerandom'

module EventService
  module GrpcClients
    class BaseClient
      include Concurrent::Async

      attr_reader :stub, :logger

      def initialize(host, port, logger = nil)
        @host = host
        @port = port
        @logger = logger || EventService.configuration.logger
        @stub = create_stub
        super()
      end

      private

      def create_stub
        raise NotImplementedError, "Subclasses must implement create_stub"
      end

      def channel
        @channel ||= GRPC::Core::Channel.new("#{@host}:#{@port}", 
                                           {},
                                           :this_channel_is_insecure)
      end

      def call_options
        {
          deadline: Time.now + 10,
          metadata: {
            'request-id' => SecureRandom.uuid,
            'timestamp' => Time.now.to_i.to_s
          }
        }
      end

      def handle_grpc_error(error, operation)
        case error
        when GRPC::NotFound
          logger.warn("#{operation}: Resource not found - #{error.message}")
          nil
        when GRPC::InvalidArgument
          logger.error("#{operation}: Invalid argument - #{error.message}")
          raise ArgumentError, error.message
        when GRPC::Unavailable
          logger.error("#{operation}: Service unavailable - #{error.message}")
          raise ServiceUnavailableError, "#{operation} service is unavailable"
        when GRPC::DeadlineExceeded
          logger.error("#{operation}: Request timeout - #{error.message}")
          raise TimeoutError, "#{operation} request timed out"
        else
          logger.error("#{operation}: Unexpected gRPC error - #{error.class}: #{error.message}")
          raise error
        end
      end
    end

    class ServiceUnavailableError < StandardError; end
    class TimeoutError < StandardError; end
  end
end