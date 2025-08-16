require 'bunny'
require 'json'
require 'concurrent'
require 'timeout'

require_relative '../clients/client_pool'

module EventService
  class EventConsumer
    include Concurrent::Async

    attr_reader :connection, :channel, :logger, :subscriptions, :client_pool

    def initialize(rabbitmq_url = nil, logger = nil)
      @rabbitmq_url = rabbitmq_url || EventService.configuration.rabbitmq_url
      @logger = setup_logger(logger || EventService.configuration.logger)
      @connection = nil
      @channel = nil
      @subscriptions = {}
      @running = false
      @client_pool = GrpcClients::ClientPool.instance
      @heartbeat_thread = nil
      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 2,
        max_threads: 10,
        max_queue: 100,
        fallback_policy: :caller_runs
      )
      super()
    end

    def connect
      max_retries = 5
      retry_count = 0
      
      begin
        @connection = Bunny.new(
          @rabbitmq_url,
          automatically_recover: true,
          network_recovery_interval: 5,
          heartbeat: 30,
          connection_timeout: 15,
          continuation_timeout: 30_000, # 30 seconds
          read_timeout: 30,
          write_timeout: 30,
          recovery_attempts: 10,
          recovery_attempts_exhausted: proc do |connection|
            logger.error("❌ RabbitMQ recovery attempts exhausted")
          end
        )
        
        logger.info("🔌 Attempting to connect to RabbitMQ: #{@rabbitmq_url}")
        logger.flush if logger.respond_to?(:flush)
        
        @connection.start
        @channel = @connection.create_channel
        @channel.prefetch(10)
        
        # Test the connection
        @channel.queue("connection_test_#{Time.now.to_i}", exclusive: true, auto_delete: true)
        
        logger.info("✅ Consumer connected to RabbitMQ successfully")
        logger.flush if logger.respond_to?(:flush)
        
      rescue => e
        retry_count += 1
        if retry_count <= max_retries
          wait_time = retry_count * 2
          logger.warn("⚠️ Connection attempt #{retry_count}/#{max_retries} failed: #{e.message}. Retrying in #{wait_time}s...")
          logger.flush if logger.respond_to?(:flush)
          sleep wait_time
          retry
        else
          logger.error("❌ Failed to connect to RabbitMQ after #{max_retries} attempts: #{e.message}")
          logger.flush if logger.respond_to?(:flush)
          raise
        end
      end
    end

    def disconnect
      @running = false
      @heartbeat_thread&.kill
      @thread_pool.shutdown
      @thread_pool.wait_for_termination(30)
      
      @subscriptions.each { |_, consumer| consumer.cancel }
      @subscriptions.clear
      @channel&.close
      @connection&.close
      
      logger.info("🔌 Consumer disconnected from RabbitMQ")
      logger.flush if logger.respond_to?(:flush)
    end

    def start_consuming
      ensure_connected
      @running = true
      
      logger.info("🚀 Started consuming events - PID: #{Process.pid}")
      logger.flush if logger.respond_to?(:flush)
      
      # Start heartbeat monitoring
      start_heartbeat_monitor
      
      # DON'T load subscriptions here - let them be loaded explicitly from start_consumer
      # This avoids blocking during startup
      
      # Simplified main loop - let RabbitMQ handle the message processing
      while @running
        begin
          # Check connection health less frequently
          check_connection_health
          log_consumer_status
          
          # Shorter sleep for more responsive shutdown
          sleep 2
        rescue Interrupt
          logger.info("🛑 Received interrupt signal, shutting down...")
          break
        rescue => e
          logger.error("❌ Error in consuming loop: #{e.message}")
          logger.flush if logger.respond_to?(:flush)
          sleep 1
        end
      end
      
      logger.info("🛑 Consumer loop ended")
    rescue => e
      logger.error("❌ Critical error in start_consuming: #{e.message}")
      logger.error(e.backtrace.join("\n"))
      logger.flush if logger.respond_to?(:flush)
      raise
    end

    def subscribe_to_events(consumer_group:, event_types:, callback: nil, &block)
      max_retries = 3
      retry_count = 0
      
      begin
        ensure_connected
        
        callback ||= block
        raise ArgumentError, "Callback or block required" unless callback

        queue_name = "#{consumer_group}_queue"
        
        logger.info("📝 Creating queue: #{queue_name}")
        logger.flush if logger.respond_to?(:flush)
        
        # Create queue with proper arguments and timeout
        queue = nil
        begin
          Timeout::timeout(15) do
            queue = @channel.queue(
              queue_name,
              durable: true,
              arguments: {
                'x-dead-letter-exchange' => 'dead_letter_exchange',
                'x-dead-letter-routing-key' => 'failed'
              }
            )
          end
        rescue Timeout::Error
          raise "Queue creation timeout for #{queue_name}"
        end

        logger.info("✅ Queue created: #{queue_name}")
        logger.flush if logger.respond_to?(:flush)

        # Bind queue to exchanges for specified event types
        event_types.each do |event_type|
          aggregate_type = extract_aggregate_type(event_type)
          exchange_name = "#{aggregate_type}.events"
          
          begin
            logger.info("🔗 Binding #{queue_name} to #{exchange_name} with key: #{event_type}")
            logger.flush if logger.respond_to?(:flush)
            
            Timeout::timeout(10) do
              exchange = @channel.exchange(exchange_name, type: :topic, durable: true, passive: true)
              queue.bind(exchange, routing_key: event_type)
            end
            
            logger.info("✅ Bound #{queue_name} to #{exchange_name} with routing key: #{event_type}")
            logger.flush if logger.respond_to?(:flush)
          rescue Bunny::NotFound => e
            logger.error("❌ Exchange #{exchange_name} does not exist: #{e.message}")
            logger.flush if logger.respond_to?(:flush)
            next
          rescue Timeout::Error => e
            logger.error("❌ Binding timeout for #{exchange_name}: #{e.message}")
            logger.flush if logger.respond_to?(:flush)
            next
          rescue => e
            logger.error("❌ Failed to bind #{queue_name} to #{exchange_name}: #{e.message}")
            logger.flush if logger.respond_to?(:flush)
            next
          end
        end

        # Start consuming with improved handling and timeout
        logger.info("🎯 Starting consumer for #{queue_name}")
        logger.flush if logger.respond_to?(:flush)
        
        consumer = nil
        begin
          Timeout::timeout(15) do
            consumer = queue.subscribe(
              manual_ack: true, 
              block: false,
              consumer_tag: "#{queue_name}_consumer_#{Time.now.to_i}",
              exclusive: false
            ) do |delivery_info, properties, payload|
              
              # Log immediately when message is received
              logger.info("📥 [#{Time.now.strftime('%H:%M:%S.%3N')}] Received: #{delivery_info.routing_key}")
              logger.flush if logger.respond_to?(:flush)
              
              # Use thread pool instead of creating new threads
              future = Concurrent::Future.execute(executor: @thread_pool) do
                process_message_safely(delivery_info, properties, payload, callback)
              end
              
              # Optional: Add timeout handling for the future
              Thread.new do
                begin
                  future.wait(60) # 60 second timeout
                rescue Concurrent::TimeoutError
                  logger.error("⏰ Message processing timeout for #{delivery_info.routing_key}")
                  logger.flush if logger.respond_to?(:flush)
                end
              end
            end
          end
        rescue Timeout::Error
          raise "Consumer subscription timeout for #{queue_name}"
        end

        @subscriptions[consumer_group] = consumer
        
        # Store subscription in database (with error handling) - make it non-blocking
        Thread.new do
          begin
            EventSubscription.create(
              consumer_group: consumer_group,
              event_types_array: event_types,
              status: 'active'
            )
            logger.info("💾 Stored subscription in database")
            logger.flush if logger.respond_to?(:flush)
          rescue => e
            logger.error("Failed to store subscription: #{e.message}")
            logger.flush if logger.respond_to?(:flush)
          end
        end

        logger.info("🎯 Successfully subscribed #{consumer_group} to events: #{event_types.join(', ')}")
        logger.flush if logger.respond_to?(:flush)
        consumer_group
        
      rescue => e
        retry_count += 1
        if retry_count <= max_retries
          wait_time = retry_count * 2
          logger.warn("⚠️ Subscription attempt #{retry_count}/#{max_retries} failed: #{e.message}. Retrying in #{wait_time}s...")
          logger.flush if logger.respond_to?(:flush)
          sleep wait_time
          retry
        else
          logger.error("❌ Failed to subscribe after #{max_retries} attempts: #{e.message}")
          logger.flush if logger.respond_to?(:flush)
          raise
        end
      end
    end

    def debug_queue_info(consumer_group)
      ensure_connected
      queue_name = "#{consumer_group}_queue"
      
      begin
        queue = @channel.queue(queue_name, passive: true)
        message_count, consumer_count = queue.status
        logger.info("🔍 Queue #{queue_name}: #{message_count} messages, #{consumer_count} consumers")
        logger.flush if logger.respond_to?(:flush)
      rescue => e
        logger.error("Failed to get queue info: #{e.message}")
        logger.flush if logger.respond_to?(:flush)
      end
    end

    private

    def setup_logger(original_logger)
      # Ensure logger doesn't buffer output
      if original_logger.respond_to?(:sync=)
        original_logger.sync = true
      end
      
      # Wrap logger to ensure immediate flushing
      LoggerWrapper.new(original_logger)
    end

    def ensure_connected
      unless @connection&.open?
        logger.info("🔄 Reconnecting to RabbitMQ...")
        logger.flush if logger.respond_to?(:flush)
        connect
      end
    end

    def start_heartbeat_monitor
      @heartbeat_thread = Thread.new do
        Thread.current.name = "heartbeat-monitor"
        
        loop do
          sleep 30
          break unless @running
          
          begin
            if @connection&.open?
              logger.debug("💓 [#{Time.now.strftime('%H:%M:%S')}] Connection alive")
            else
              logger.warn("💔 Connection dead, reconnecting...")
              logger.flush if logger.respond_to?(:flush)
              ensure_connected
            end
          rescue => e
            logger.error("❌ Heartbeat error: #{e.message}")
            logger.flush if logger.respond_to?(:flush)
          end
        end
      end
    end

    def check_connection_health
      unless @connection&.open?
        logger.warn("⚠️ Connection lost, attempting to reconnect...")
        logger.flush if logger.respond_to?(:flush)
        ensure_connected
      end
    end

    def log_consumer_status
      active_count = @subscriptions.count
      pool_stats = @thread_pool.length rescue 0
      queue_size = @thread_pool.queue_length rescue 0
      
      logger.info("📊 [#{Time.now.strftime('%H:%M:%S')}] Subscriptions: #{active_count} | Threads: #{pool_stats} | Queue: #{queue_size}")
      logger.flush if logger.respond_to?(:flush)
    end

    def process_message_safely(delivery_info, properties, payload, callback)
      start_time = Time.now
      thread_name = Thread.current.name = "msg-processor-#{start_time.to_i}"
      
      begin
        event_data = JSON.parse(payload)
        event_id = event_data['id']
        event_type = event_data['event_type']
        
        logger.info("🔄 [#{Thread.current.name}] Processing: #{event_id} - #{event_type}")
        logger.flush if logger.respond_to?(:flush)
        
        # Add timeout for callback processing
        timeout_seconds = 30
        begin
          Timeout::timeout(timeout_seconds) do
            callback.call(event_data)
          end
        rescue Timeout::Error
          raise "Callback processing timeout after #{timeout_seconds} seconds"
        end
        
        # Acknowledge the message
        @channel.ack(delivery_info.delivery_tag)
        
        processing_time = (Time.now - start_time).round(3)
        logger.info("✅ [#{thread_name}] Completed: #{event_id} in #{processing_time}s")
        logger.flush if logger.respond_to?(:flush)
        
      rescue JSON::ParserError => e
        logger.error("❌ [#{thread_name}] Invalid JSON: #{e.message}")
        logger.error("Raw payload: #{payload}")
        logger.flush if logger.respond_to?(:flush)
        @channel.nack(delivery_info.delivery_tag, false, false)
        
      rescue => e
        processing_time = (Time.now - start_time).round(3)
        logger.error("❌ [#{thread_name}] Failed after #{processing_time}s: #{e.message}")
        logger.error("Event payload: #{payload}")
        logger.error("Error: #{e.backtrace.first(5).join("\n")}")
        logger.flush if logger.respond_to?(:flush)
        
        # Try to parse for error handling
        begin
          event_data = JSON.parse(payload)
          handle_processing_failure(event_data, delivery_info, e)
        rescue JSON::ParserError
          logger.error("Could not parse payload for error handling")
          logger.flush if logger.respond_to?(:flush)
        end
        
        # Reject and don't requeue (will go to DLQ)
        @channel.nack(delivery_info.delivery_tag, false, false)
      end
    rescue => e
      logger.error("❌ Critical error in message processing: #{e.message}")
      logger.error(e.backtrace.join("\n"))
      logger.flush if logger.respond_to?(:flush)
      
      # Try to nack the message if possible
      begin
        @channel.nack(delivery_info.delivery_tag, false, false) if delivery_info
      rescue => nack_error
        logger.error("Failed to nack message: #{nack_error.message}")
        logger.flush if logger.respond_to?(:flush)
      end
    end

    def extract_aggregate_type(event_type)
      event_type.split(/[._]/).first
    end

    def load_subscriptions
      begin
        subscriptions = EventSubscription.active_subscriptions
        logger.info("📚 Loading #{subscriptions.count} active subscriptions from database")
        logger.flush if logger.respond_to?(:flush)
        
        subscriptions.each do |subscription|
          logger.info("Loading subscription: #{subscription.consumer_group} - #{subscription.event_types_array}")
          logger.flush if logger.respond_to?(:flush)
          
          subscribe_to_events(
            consumer_group: subscription.consumer_group,
            event_types: subscription.event_types_array
          ) do |event|
            route_event(event)
          end
        end
      rescue => e
        logger.error("Failed to load subscriptions: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        logger.flush if logger.respond_to?(:flush)
      end
    end

    def route_event(event)
      event_type = event['event_type']
      event_data = event['event_data'] || {}
      
      logger.info("🎯 [#{Time.now.strftime('%H:%M:%S.%3N')}] Routing: #{event_type} for #{event['aggregate_type']}:#{event['aggregate_id']}")
      logger.flush if logger.respond_to?(:flush)
      
      case event_type
      when 'user.created'
        user_id = event_data['user_id'] || event_data['userId']
        logger.info("👤 User created: #{user_id}")
      when 'user.updated'
        user_id = event_data['user_id'] || event_data['userId']
        logger.info("👤 User updated: #{user_id}")
      when 'user.deleted'
        handle_user_deleted(event)
      when 'post.created'
        post_id = event_data['post_id'] || event_data['postId']
        user_id = event_data['user_id'] || event_data['userId']
        logger.info("📝 Post created: #{post_id} by user: #{user_id}")
      when 'post.updated'
        post_id = event_data['post_id'] || event_data['postId']
        user_id = event_data['user_id'] || event_data['userId']
        logger.info("📝 Post updated: #{post_id} by user: #{user_id}")
      when 'post.deleted'
        handle_post_deleted(event)
      else
        logger.warn("⚠️ Unknown event type: #{event_type}")
      end
      
      logger.flush if logger.respond_to?(:flush)
    rescue => e
      logger.error("❌ Error routing event #{event['id']} (#{event_type}): #{e.message}")
      logger.error("Event data: #{event}")
      logger.error("Error: #{e.backtrace.first(3).join("\n")}")
      logger.flush if logger.respond_to?(:flush)
      raise e
    end

    def handle_user_deleted(event)
      user_id = event['aggregate_id']
      event_data = event['event_data'] || {}
      
      user_id ||= event_data['user_id'] || event_data['userId']
      user_id = user_id.to_s if user_id

      logger.info("🗑️ [START] Processing user deletion: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

      # Process each service with individual error handling and immediate logging
      delete_user_comments(user_id)
      delete_user_likes(user_id)
      delete_user_posts(user_id)
      delete_user(user_id)
      
      logger.info("🗑️ [DONE] User deletion completed: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

    rescue StandardError => e
      logger.error("❌ Error handling user.deleted for #{user_id}: #{e.message}")
      logger.error(e.backtrace.join("\n"))
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_user_comments(user_id)
      logger.info("🔄 Deleting comments for user: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

      @client_pool.with_comment_client do |comment_client|
        logger.info("🔍 Calling get_comments_by_user with user_id: \"#{user_id}\"")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          # Fixed: Use keyword arguments to match the method signature
          comments_response = comment_client.get_comments_by_user(user_id: user_id)
          logger.info("Comments response: #{comments_response.inspect}")
          logger.flush if logger.respond_to?(:flush)
          
          # Check if the response is nil due to parsing error
          if comments_response.nil?
            logger.warn("⚠️ Comments response is nil - may indicate server error or parsing issue")
            logger.flush if logger.respond_to?(:flush)
            return
          end
          
          # Check if the server response indicates success and has comments
          # Based on C# server code, the response should have a 'success' field and 'comments' field
          if comments_response.success && comments_response.comments&.any?
            # Fixed: Use empty array instead of nil, and correct parameter name
            success = comment_client.delete_comments(user_ids: [user_id], post_ids: [])
            if success
              logger.info("✅ Deleted comments for user: #{user_id}")
            else
              logger.error("❌ Failed to delete comments for user: #{user_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          elsif comments_response.success
            logger.info("ℹ️ No comments found for user: #{user_id}")
            logger.flush if logger.respond_to?(:flush)
          else
            logger.warn("⚠️ Server returned unsuccessful response: #{comments_response.message}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: get_comments_by_user - #{e.message}")
          logger.info("ℹ️ Skipping comment deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error with comments for user #{user_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        rescue StandardError => e
          logger.error("❌ Unexpected error with comments for user #{user_id}: #{e.message}")
          logger.error("Error class: #{e.class}")
          logger.error(e.backtrace.join("\n")) if e.backtrace
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting comments for user #{user_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_user_likes(user_id)
      logger.info("🔄 Deleting likes for user: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

      @client_pool.with_like_client do |like_client|
        logger.info("🔍 Calling get_user_likes with user_id: \"#{user_id}\"")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          liked_response = like_client.get_user_likes(user_id)
          logger.info("Likes response: #{liked_response.inspect}")
          logger.flush if logger.respond_to?(:flush)
          
          if liked_response&.likes&.any?
            success = like_client.unlike_posts(user_ids: [user_id], post_ids: [])
            if success
              logger.info("✅ Deleted likes for user: #{user_id}")
            else
              logger.error("❌ Failed to delete likes for user: #{user_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          else
            logger.info("ℹ️ No likes found for user: #{user_id}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: get_user_likes - #{e.message}")
          logger.info("ℹ️ Skipping like deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error deleting likes for user #{user_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting likes for user #{user_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_user_posts(user_id)
      logger.info("🔄 Deleting posts for user: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

      @client_pool.with_post_client do |post_client|
        logger.info("🔍 Calling list_posts with user_id: #{user_id}")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          posts_response = post_client.get_posts_by_user(user_id)
          logger.info("Posts response: #{posts_response.inspect}")
          logger.flush if logger.respond_to?(:flush)
          
          if posts_response&.posts&.any?
            success = post_client.delete_posts([], [user_id])
            if success
              logger.info("✅ Deleted posts for user: #{user_id}")
            else
              logger.error("❌ Failed to delete posts for user: #{user_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          else
            logger.info("ℹ️ No posts found for user: #{user_id}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: list_posts - #{e.message}")
          logger.info("ℹ️ Skipping post deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error deleting posts for user #{user_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting posts for user #{user_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_user(user_id)
      logger.info("🔄 Deleting user: #{user_id}")
      logger.flush if logger.respond_to?(:flush)

      @client_pool.with_user_client do |user_client|
        logger.info("🔍 Calling get_local_user with user_id: #{user_id}")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          user_response = user_client.get_local_user(user_id)
          logger.info("User response: #{user_response.inspect}")
          logger.flush if logger.respond_to?(:flush)
          
          if user_response&.success && user_response&.user
            success = user_client.delete_user(user_id)
            if success
              logger.info("✅ Deleted user: #{user_id}")
            else
              logger.error("❌ Failed to delete user: #{user_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          else
            logger.info("ℹ️ No user found for deletion: #{user_id}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: get_local_user - #{e.message}")
          logger.info("ℹ️ Skipping user deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error deleting user #{user_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting user #{user_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def handle_post_deleted(event)
      post_id = event['aggregate_id']
      logger.info("🗑️ [START] Processing post deletion: #{post_id}")
      logger.flush if logger.respond_to?(:flush)

      delete_post_comments(post_id.to_i)
      delete_post_likes(post_id.to_i)

      logger.info("🗑️ [DONE] Post deletion completed: #{post_id}")
      logger.flush if logger.respond_to?(:flush)

    rescue StandardError => e
      logger.error("❌ Error handling post.deleted for #{post_id}: #{e.message}")
      logger.error(e.backtrace.join("\n"))
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_post_comments(post_id)
      logger.info("🔄 Deleting comments for post: #{post_id}")
      logger.flush if logger.respond_to?(:flush)
      
      @client_pool.with_comment_client do |comment_client|
        logger.info("🔍 Calling get_comments_by_post with post_id: #{post_id}")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          comments_response = comment_client.get_comments_by_post(post_id: post_id)
          if comments_response&.comments&.any?
            success = comment_client.delete_comments(user_ids: [], post_ids: [post_id])
            if success
              logger.info("✅ Deleted comments for post: #{post_id}")
            else
              logger.error("❌ Failed to delete comments for post: #{post_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          else
            logger.info("ℹ️ No comments found for post: #{post_id}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: get_comments_by_post - #{e.message}")
          logger.info("ℹ️ Skipping comment deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error deleting comments for post #{post_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting comments for post #{post_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def delete_post_likes(post_id)
      logger.info("🔄 Deleting likes for post: #{post_id}")
      logger.flush if logger.respond_to?(:flush)
      
      @client_pool.with_like_client do |like_client|
        logger.info("🔍 Calling get_post_likes with post_id: #{post_id}")
        logger.flush if logger.respond_to?(:flush)
        
        begin
          liked_response = like_client.get_post_likes(post_id)
          if liked_response&.likes&.any?
            success = like_client.unlike_posts(user_ids: nil, post_ids: [post_id])
            if success
              logger.info("✅ Deleted likes for post: #{post_id}")
            else
              logger.error("❌ Failed to delete likes for post: #{post_id}")
            end
            logger.flush if logger.respond_to?(:flush)
          else
            logger.info("ℹ️ No likes found for post: #{post_id}")
            logger.flush if logger.respond_to?(:flush)
          end
        rescue GRPC::Unimplemented => e
          logger.error("❌ gRPC method not implemented: get_post_likes - #{e.message}")
          logger.info("ℹ️ Skipping like deletion due to unimplemented method")
          logger.flush if logger.respond_to?(:flush)
        rescue GRPC::BadStatus => e
          logger.error("❌ gRPC error deleting likes for post #{post_id}: #{e.message} (code: #{e.code})")
          logger.flush if logger.respond_to?(:flush)
        end
      end
    rescue => e
      logger.error("❌ Error deleting likes for post #{post_id}: #{e.message}")
      logger.error("Error class: #{e.class}")
      logger.flush if logger.respond_to?(:flush)
    end

    def handle_processing_failure(event_data, delivery_info, error)
      DeadLetterEvent.create(
        original_event_id: event_data['id'],
        exchange_name: delivery_info.exchange,
        routing_key: delivery_info.routing_key,
        event_payload: event_data.to_json,
        error_message: error.message
      )
    rescue => e
      logger.error("Failed to create dead letter event: #{e.message}")
      logger.flush if logger.respond_to?(:flush)
    end
  end

  # Logger wrapper to ensure immediate flushing
  class LoggerWrapper
    def initialize(logger)
      @logger = logger
    end

    def method_missing(method, *args, &block)
      result = @logger.send(method, *args, &block)
      flush if respond_to?(:flush)
      result
    end

    def respond_to_missing?(method, include_private = false)
      @logger.respond_to?(method, include_private)
    end

    def flush
      @logger.flush if @logger.respond_to?(:flush)
      STDOUT.flush
    end
  end
end