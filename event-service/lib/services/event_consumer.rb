require 'bunny'
require 'json'
require 'concurrent'

require_relative '../clients/client_pool'

module EventService
  class EventConsumer
    include Concurrent::Async

    attr_reader :connection, :channel, :logger, :subscriptions, :client_pool

    def initialize(rabbitmq_url = nil, logger = nil)
      @rabbitmq_url = rabbitmq_url || EventService.configuration.rabbitmq_url
      @logger = logger || EventService.configuration.logger
      @connection = nil
      @channel = nil
      @subscriptions = {}
      @running = false
      @client_pool = GrpcClients::ClientPool.instance
      super()
    end

    def connect
      @connection = Bunny.new(@rabbitmq_url)
      @connection.start
      @channel = @connection.create_channel
      @channel.prefetch(10) # Process max 10 messages at a time
      
      logger.info("Consumer connected to RabbitMQ: #{@rabbitmq_url}")
    end

    def disconnect
      @running = false
      @subscriptions.each { |_, consumer| consumer.cancel }
      @subscriptions.clear
      @channel&.close
      @connection&.close
      logger.info("Consumer disconnected from RabbitMQ")
    end

    def start_consuming
      ensure_connected
      @running = true
      
      # Load active subscriptions from database
      load_subscriptions
      
      logger.info("Started consuming events")
      
      # Keep the consumer running
      loop do
        break unless @running
        sleep 1
      end
    end

    def subscribe_to_events(consumer_group:, event_types:, callback: nil, &block)
      ensure_connected
      
      callback ||= block
      raise ArgumentError, "Callback or block required" unless callback

      queue_name = "#{consumer_group}_queue"
      queue = @channel.queue(
        queue_name,
        durable: true,
        arguments: {
          'x-dead-letter-exchange' => 'dead_letter_exchange',
          'x-dead-letter-routing-key' => 'failed'
        }
      )

      # Bind queue to exchanges for specified event types
      event_types.each do |event_type|
        aggregate_type = event_type.split('.').first
        exchange_name = "#{aggregate_type}.events"
        
        if @channel.exchange_exists?(exchange_name)
          queue.bind(exchange_name, routing_key: event_type)
          logger.info("Bound #{queue_name} to #{exchange_name}:#{event_type}")
        end
      end

      # Start consuming
      consumer = queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
        process_message(delivery_info, properties, payload, callback)
      end

      @subscriptions[consumer_group] = consumer
      
      # Store subscription in database
      EventSubscription.create(
        consumer_group: consumer_group,
        event_types_array: event_types,
        status: 'active'
      )

      logger.info("Subscribed #{consumer_group} to events: #{event_types}")
      consumer_group
    end

    private

    def ensure_connected
      connect unless @connection&.open?
    end

    def load_subscriptions
      EventSubscription.active_subscriptions.each do |subscription|
        subscribe_to_events(
          consumer_group: subscription.consumer_group,
          event_types: subscription.event_types_array
        ) do |event|
          # Default handler - log the event
          route_event(event)
          logger.info("Received event: #{event['event_type']} for #{event['aggregate_type']}:#{event['aggregate_id']}")
        end
      end
    end

    def route_event(event)
      event_type = event['event_type']
      
      case event_type
      # User events
      when 'user.created'
        user_id = event_data['user_id']
        logger.info("User created: #{user_id}")
      when 'user.updated'
        user_id = event_data['user_id']
        logger.info("User updated: #{user_id}")
      when 'user.deleted'
        handle_user_deleted(event)
      
      # Post events
      when 'post.created'
        post_id = event_data['post_id']
        user_id = event_data['user_id']
        logger.info("Post created: #{post_id} by user: #{user_id}")
      when 'post.updated'
        post_id = event_data['post_id']
        user_id = event_data['user_id']
        logger.info("Post updated: #{post_id} by user: #{user_id}")
      when 'post.deleted'
        handle_post_deleted(event)

      else
        logger.warn("Unknown event type: #{event_type}")
      end
    rescue => e
      logger.error("Error routing event #{event['id']} (#{event_type}): #{e.message}")
      raise e
    end

    def handle_user_deleted(event)
      user_id = event['aggregate_id']
      logger.info("User deleted: #{user_id}")

      # Delete posts
      @client_pool.with_post_client do |post_client|
        posts_response = post_client.list_posts(user_id: user_id)
        if posts_response&.posts&.any?
          success = post_client.delete_posts(user_ids: [user_id])
          success ? logger.info("Deleted posts for user: #{user_id}") : logger.error("Failed to delete posts for user: #{user_id}")
        else
          logger.info("No posts found for user.")
        end
      end

      # Delete comments
      @client_pool.with_comment_client do |comment_client|
        comments_response = comment_client.get_comments_by_user(user_id: user_id)
        if comments_response&.comments&.any?
          success = comment_client.delete_comments(user_ids: [user_id])
          success ? logger.info("Deleted comments for user: #{user_id}") : logger.error("Failed to delete comments for user: #{user_id}")
        else
          logger.info("No comments found for user.")
        end
      end

      # Delete likes
      @client_pool.with_like_client do |like_client|
        liked_response = like_client.get_user_likes(user_id)
        if liked_response&.likes&.any?
          success = like_client.unlike_post(user_ids: [user_id])
          success ? logger.info("Deleted like for user: #{user_id}") : logger.error("Failed to delete like for user: #{user_id}")
        else
          logger.info("No likes found for user.")
        end
      end

    rescue StandardError => e
      logger.error("Error handling user.deleted for #{user_id}: #{e.message}")
    end


    def handle_post_deleted(event)
      post_id = event['aggregate_id']
      logger.info("Post deleted: #{post_id}")

      # Delete comments
      @client_pool.with_comment_client do |comment_client|
        comments_response = comment_client.get_comments_by_post(post_id: post_id)
        if comments_response&.comments&.any?
          success = comment_client.delete_comments(post_ids:[post_id])
          success ? logger.info("Deleted comments for post: #{post_id}") : logger.error("Failed to delete comments for post: #{post_id}")
        else
          logger.info("No comments found for post.")
        end
      end

      # Delete likes
      @client_pool.with_like_client do |like_client|
        liked_response = like_client.get_post_likes(post_id)
        if liked_response&.likes&.any?
          success = like_client.unlike_post(post_ids: [post_id])
          success ? logger.info("Deleted like for post: #{post_id}") : logger.error("Failed to delete like for post: #{post_id}")
        else
          logger.info("No likes found for post.")
        end
      end
    rescue StandardError => e
      logger.error("Error handling user.deleted for #{user_id}: #{e.message}")
    end

    def process_message(delivery_info, properties, payload, callback)
      event_data = JSON.parse(payload)
      
      logger.info("Processing event: #{event_data['id']}")
      
      begin
        # Call the callback with the event data
        callback.call(event_data)
        
        # Acknowledge the message
        @channel.ack(delivery_info.delivery_tag)
        
        logger.info("Successfully processed event: #{event_data['id']}")
      rescue => e
        logger.error("Failed to process event #{event_data['id']}: #{e.message}")
        
        # Reject and requeue the message (will go to DLQ after max retries)
        @channel.nack(delivery_info.delivery_tag, false, false)
        
        # Store in dead letter events table
        handle_processing_failure(event_data, delivery_info, e)
      end
    rescue JSON::ParserError => e
      logger.error("Invalid JSON payload: #{e.message}")
      @channel.nack(delivery_info.delivery_tag, false, false)
    end

    def handle_processing_failure(event_data, delivery_info, error)
      DeadLetterEvent.create(
        original_event_id: event_data['id'],
        exchange_name: delivery_info.exchange,
        routing_key: delivery_info.routing_key,
        event_payload: event_data.to_json,
        error_message: error.message
      )
    end
  end
end