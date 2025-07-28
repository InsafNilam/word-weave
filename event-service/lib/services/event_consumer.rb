require 'bunny'
require 'json'
require 'concurrent'

module EventService
  class EventConsumer
    include Concurrent::Async

    attr_reader :connection, :channel, :logger, :subscriptions

    def initialize(rabbitmq_url = nil, logger = nil)
      @rabbitmq_url = rabbitmq_url || EventService.configuration.rabbitmq_url
      @logger = logger || EventService.configuration.logger
      @connection = nil
      @channel = nil
      @subscriptions = {}
      @running = false
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
          logger.info("Received event: #{event['event_type']} for #{event['aggregate_type']}:#{event['aggregate_id']}")
        end
      end
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