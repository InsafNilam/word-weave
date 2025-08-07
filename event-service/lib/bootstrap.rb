#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'thread'

# Bootstrap module for Event Service
module EventServiceBootstrap
  class LoadError < StandardError; end
  class ServiceError < StandardError; end

  @logger = Logger.new($stdout)
  @logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO').upcase)
  @shutdown_flag = false
  @shutdown_mutex = Mutex.new 
  @shutdown_handlers = []

  class << self
    attr_reader :logger, :shutdown_flag, :shutdown_mutex

    # Main initialization method with proper error handling
    def initialize!
      logger.info 'Starting Event Service initialization...'
      
      load_configuration
      initialize_event_service_config  # Only initialize config, not database
      load_dependencies
      
      logger.info 'Event Service initialization completed successfully'
    rescue StandardError => e
      logger.error "Failed to initialize Event Service: #{e.message}"
      logger.error e.backtrace.join("\n")
      raise LoadError, "Initialization failed: #{e.message}"
    end

    # Start database setup - this should be run before starting services
    def start_setup
      logger.info 'Starting database setup...'

      # Ensure initialization is done first
      initialize! unless @initialized

      setup = DatabaseSetup.new
      setup.run

      logger.info 'Database setup completed successfully'
    rescue StandardError => e
      logger.error "Failed during database setup: #{e.message}"
      logger.debug e.backtrace.join("\n") if debug_mode?
      raise ServiceError, "Setup failed: #{e.message}"
    end

    def start_server(port: ENV.fetch('GRPC_PORT', '50055'), host: ENV.fetch('GRPC_HOST', '0.0.0.0'))
      # Ensure initialization and setup are done
      initialize! unless @initialized
      ensure_database_ready
      
      validate_port!(port)
      
      server = create_grpc_server
      bind_address = "#{host}:#{port}"
      
      server.add_http2_port(bind_address, server_credentials)
      server.handle(EventService::GrpcServer.new)
      
      setup_server_shutdown_handlers(server)
      
      logger.info "Event Service gRPC server starting on #{bind_address}"
      server.run_till_terminated_or_interrupted(['INT', 'TERM'])
    rescue StandardError => e
      logger.error "Failed to start gRPC server: #{e.message}"
      raise ServiceError, "Server startup failed: #{e.message}"
    end

    # Start event consumer with connection management
    def start_consumer
      logger.info 'Starting Event Consumer...'
      
      # Ensure initialization and setup are done
      initialize! unless @initialized
      ensure_database_ready
      
      consumer = EventService::EventConsumer.new
      setup_consumer_shutdown_handlers(consumer)
      
      consumer.connect
      logger.info 'Event Consumer connected successfully'
      
      consumer.start_consuming
    rescue StandardError => e
      logger.error "Failed to start consumer: #{e.message}"
      consumer&.disconnect
      raise ServiceError, "Consumer startup failed: #{e.message}"
    end

    # Start dead letter handler with proper lifecycle management
    def start_dead_letter_handler
      logger.info 'Starting Dead Letter Handler...'

      # Ensure initialization and setup are done
      initialize! unless @initialized
      ensure_database_ready

      handler = EventService::DeadLetterHandler.new
      setup_dead_letter_shutdown_handlers(handler)
      
      handler.start
      logger.info 'Dead Letter Handler started successfully'
      
      keep_alive_loop
    rescue StandardError => e
      logger.error "Failed to start dead letter handler: #{e.message}"
      handler&.stop
      raise ServiceError, "Dead letter handler startup failed: #{e.message}"
    end

    # Method for worker threads to check if they should shut down
    def should_shutdown?
      @shutdown_mutex.synchronize { @shutdown_flag }
    end

    # Method to signal all threads to shut down
    def signal_shutdown
      @shutdown_mutex.synchronize { @shutdown_flag = true }
      logger.info 'Shutdown signal received. Initiating graceful shutdown...'
    end
    
    # Start all services (useful for development/testing)
    def start_all_services
      # First ensure database is set up
      start_setup
      
      threads = []

      # Start services in separate threads
      threads << Thread.new do
        Thread.current.name = "server-thread"
        start_server_with_shutdown_check
      end
      
      threads << Thread.new do
        Thread.current.name = "consumer-thread"
        start_consumer_with_shutdown_check
      end
      
      threads << Thread.new do
        Thread.current.name = "dead-letter-thread"
        start_dead_letter_handler_with_shutdown_check
      end

      logger.info 'All services started. Press Ctrl+C to stop.'

      begin
        # Wait for all threads to complete
        threads.each(&:join)
      rescue Interrupt
        logger.info 'Interrupt received, initiating shutdown...'
        signal_shutdown
        
        # Wait for threads to finish gracefully
        shutdown_timeout = 15 # seconds
        threads.each do |thread|
          next unless thread.alive?
          
          logger.info "Waiting for #{thread.name || thread.object_id} to shut down..."
          unless thread.join(shutdown_timeout)
            logger.warn "#{thread.name || thread.object_id} did not shut down gracefully. Force killing..."
            thread.kill
          else
            logger.info "#{thread.name || thread.object_id} shut down gracefully"
          end
        end
      ensure
        # Final cleanup - force kill any remaining threads
        threads.each do |thread|
          if thread.alive?
            logger.warn "Force killing remaining thread: #{thread.name || thread.object_id}"
            thread.kill
          end
        end
        logger.info 'All services stopped.'
      end
    end

    # Modified service startup methods that respect shutdown signals
    def start_server_with_shutdown_check(port: ENV.fetch('GRPC_PORT', '50055'), host: ENV.fetch('GRPC_HOST', '0.0.0.0'))
      ensure_database_ready
      
      validate_port!(port)
      
      server = create_grpc_server
      bind_address = "#{host}:#{port}"
      
      server.add_http2_port(bind_address, server_credentials)
      server.handle(EventService::GrpcServer.new)
      
      logger.info "Event Service gRPC server starting on #{bind_address}"
      
      # Start server in a separate thread so we can check shutdown flag
      server_thread = Thread.new { server.run }
      
      # Monitor shutdown flag
      until should_shutdown?
        sleep(1)
        break unless server_thread.alive?
      end
      
      logger.info 'Stopping gRPC server due to shutdown signal...'
      server.stop
      server_thread.join(5) # Wait up to 5 seconds for graceful shutdown
      
    rescue StandardError => e
      logger.error "Failed to start gRPC server: #{e.message}"
      raise ServiceError, "Server startup failed: #{e.message}"
    end

    def start_consumer_with_shutdown_check
      logger.info 'Starting Event Consumer...'
      
      ensure_database_ready
      
      consumer = EventService::EventConsumer.new
      consumer.connect
      logger.info 'Event Consumer connected successfully'
      
      # Start consuming in a way that respects shutdown signals
      consumer_thread = Thread.new { consumer.start_consuming }
      
      # Monitor shutdown flag
      until should_shutdown?
        sleep(1)
        break unless consumer_thread.alive?
      end
      
      logger.info 'Stopping Event Consumer due to shutdown signal...'
      consumer.disconnect
      consumer_thread.join(5) # Wait for graceful shutdown
      
    rescue StandardError => e
      logger.error "Failed to start consumer: #{e.message}"
      consumer&.disconnect
      raise ServiceError, "Consumer startup failed: #{e.message}"
    end

    def start_dead_letter_handler_with_shutdown_check
      logger.info 'Starting Dead Letter Handler...'

      ensure_database_ready

      handler = EventService::DeadLetterHandler.new
      handler.start
      logger.info 'Dead Letter Handler started successfully'
      
      # Keep alive loop that respects shutdown signals
      until should_shutdown?
        sleep(1)
      end
      
      logger.info 'Stopping Dead Letter Handler due to shutdown signal...'
      handler.stop
      
    rescue StandardError => e
      logger.error "Failed to start dead letter handler: #{e.message}"
      handler&.stop
      raise ServiceError, "Dead letter handler startup failed: #{e.message}"
    end

    # Graceful shutdown of all registered handlers
    def shutdown!
      logger.info 'Initiating graceful shutdown...'
      
      @shutdown_handlers.each do |handler|
        begin
          handler.call
        rescue StandardError => e
          logger.error "Error during shutdown: #{e.message}"
        end
      end
      
      logger.info 'Shutdown completed'
    end

    private

    def load_configuration
      logger.debug 'Loading configuration...'
      require_relative 'configuration'
    end

    def initialize_event_service_config
      logger.debug 'Initializing EventService configuration...'
      EventService.initialize!  # This now only validates config, doesn't connect to DB
      @initialized = true
    end

    def load_dependencies
      logger.debug 'Loading dependencies...'

      # Load database setup first
      load_setup
      
      # Load models (but don't instantiate them yet)
      load_models
      
      # Load services (but don't start them yet)  
      load_services
      
      # Load types and validators
      load_types_and_validators
      
      # Load gRPC components
      load_grpc_components
    end

    def ensure_database_ready
      unless @database_ready
        logger.info 'Database connection not established. Running setup first...'
        setup = DatabaseSetup.new
        setup.run
        
        # Now establish the database connection
        EventService.configuration.database
        @database_ready = true
        
        logger.info 'Database is now ready.'
      end
    end

    def debug_mode?
      ENV['DEBUG'] == 'true' || ENV.fetch('LOG_LEVEL', 'INFO').upcase == 'DEBUG'
    end

    def load_setup
      %w[
        ../db/setup
      ].each { |file| require_relative file }
    end

    def load_models
      %w[
        models/event
        models/dead_letter_event
        models/event_subscription
      ].each do |file|
        begin
          require_relative file
        rescue LoadError => e
          logger.warn "Could not load model #{file}: #{e.message}"
        end
      end
    end

    def load_services
      %w[
        services/event_store
        services/event_consumer
        services/event_publisher
        services/dead_letter_handler
      ].each do |file|
        begin
          require_relative file
        rescue LoadError => e
          logger.warn "Could not load service #{file}: #{e.message}"
        end
      end
    end

    def load_types_and_validators
      %w[
        types/event_types
        validators/event_validator
      ].each do |file|
        begin
          require_relative file
        rescue LoadError => e
          logger.warn "Could not load #{file}: #{e.message}"
        end
      end
    end

    def load_grpc_components
      begin
        require_relative 'grpc/server'
      rescue LoadError => e
        logger.warn "Could not load gRPC server: #{e.message}"
      end
    end

    def create_grpc_server
      GRPC::RpcServer.new(
        pool_size: ENV.fetch('GRPC_POOL_SIZE', 30).to_i,
        max_waiting_requests: ENV.fetch('GRPC_MAX_WAITING', 20).to_i,
        poll_period: ENV.fetch('GRPC_POLL_PERIOD', 1).to_i
      )
    end

    def server_credentials
      if ENV['GRPC_USE_TLS'] == 'true'
        # Load TLS credentials if configured
        GRPC::Core::ServerCredentials.new(nil, nil, false)
      else
        :this_port_is_insecure
      end
    end

    def validate_port!(port)
      port_num = port.to_i
      raise ArgumentError, "Invalid port: #{port}" unless port_num.between?(1, 65535)
    end

    def setup_server_shutdown_handlers(server)
      shutdown_handler = lambda do
        logger.info 'Shutting down gRPC server...'
        server.stop
      end
      
      register_signal_handlers(shutdown_handler)
    end

    def setup_consumer_shutdown_handlers(consumer)
      shutdown_handler = lambda do
        logger.info 'Shutting down Event Consumer...'
        consumer.disconnect
      end
      
      register_signal_handlers(shutdown_handler)
    end

    def setup_dead_letter_shutdown_handlers(handler)
      shutdown_handler = lambda do
        logger.info 'Shutting down Dead Letter Handler...'
        handler.stop
      end
      
      register_signal_handlers(shutdown_handler)
    end

    def register_signal_handlers(shutdown_handler)
      @shutdown_handlers << shutdown_handler
      
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          shutdown!
          exit(0)
        end
      end
    end

    def keep_alive_loop
      loop do
        sleep 1
      rescue Interrupt
        break
      end
    end
  end
end

# Maintain backward compatibility
module EventService
  extend EventServiceBootstrap
end