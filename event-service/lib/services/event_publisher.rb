require 'bunny'
require 'json'

module EventService
  class EventPublisher
    attr_reader :connection, :channel, :logger

    def initialize(rabbitmq_url = nil, logger = nil)
      @rabbitmq_url = rabbitmq_url || EventService.configuration.rabbitmq_url
      @logger = logger || EventService.configuration.logger
      @connection = nil
      @channel = nil
      @exchanges = {}
    end

    def connect
      @connection = Bunny.new(@rabbitmq_url)
      @connection.start
      @channel = @connection.create_channel
      
      setup_exchanges
      setup_dead_letter_queues
      
      logger.info("Connected to RabbitMQ: #{@rabbitmq_url}")
    end

    def disconnect
      @channel&.close
      @connection&.close
      logger.info("Disconnected from RabbitMQ")
    end

    def publish_event(event)
      ensure_connected
      
      exchange_name = "#{event.aggregate_type}.events"
      routing_key = event.event_type
      
      exchange = @exchanges[exchange_name]
      raise "Exchange #{exchange_name} not found" unless exchange

      message = {
        id: event.id,
        aggregate_id: event.aggregate_id,
        aggregate_type: event.aggregate_type,
        event_type: event.event_type,
        event_data: JSON.parse(event.event_data),
        metadata: event.metadata ? JSON.parse(event.metadata) : {},
        version: event.version,
        timestamp: event.timestamp,
        correlation_id: event.correlation_id,
        causation_id: event.causation_id
      }

      exchange.publish(
        message.to_json,
        routing_key: routing_key,
        persistent: true,
        message_id: event.id,
        timestamp: event.timestamp,
        headers: {
          aggregate_id: event.aggregate_id,
          aggregate_type: event.aggregate_type,
          event_type: event.event_type,
          correlation_id: event.correlation_id,
          causation_id: event.causation_id
        }
      )

      logger.info("Published event: #{event.id} to #{exchange_name}:#{routing_key}")
      true
    rescue => e
      logger.error("Failed to publish event #{event&.id}: #{e.message}")
      handle_publish_failure(event, exchange_name, routing_key, e)
      false
    end

    def publish_domain_event(aggregate_id:, aggregate_type:, event_type:, event_data:,
                           metadata: {}, correlation_id: nil, causation_id: nil)
      # First store the event
      event_store = EventStore.new
      event = event_store.store_event(
        aggregate_id: aggregate_id,
        aggregate_type: aggregate_type,
        event_type: event_type,
        event_data: event_data,
        metadata: metadata,
        correlation_id: correlation_id,
        causation_id: causation_id
      )

      # Then publish it
      publish_event(event)
      event
    end

    private

    def ensure_connected
      connect unless @connection&.open?
    end

    def setup_exchanges
      exchange_configs = [
        { name: 'user.events', type: :topic, durable: true },
        { name: 'post.events', type: :topic, durable: true },
        { name: 'comment.events', type: :topic, durable: true },
        { name: 'like.events', type: :topic, durable: true }
      ]

      exchange_configs.each do |config|
        @exchanges[config[:name]] = @channel.exchange(
          config[:name],
          type: config[:type],
          durable: config[:durable]
        )
        logger.info("Created exchange: #{config[:name]}")
      end
    end

    def setup_dead_letter_queues
      # Create dead letter exchange
      dlx = @channel.exchange('dead_letter_exchange', type: :direct, durable: true)
      
      # Create dead letter queue
      dlq = @channel.queue(
        'dead_letter_queue',
        durable: true,
        arguments: {
          'x-message-ttl' => 86400000, # 24 hours
          'x-max-retries' => 3
        }
      )
      
      dlq.bind(dlx, routing_key: 'failed')
      logger.info("Setup dead letter queue")
    end

    def handle_publish_failure(event, exchange_name, routing_key, error)
      return unless event

      DeadLetterEvent.create(
        original_event_id: event.id,
        exchange_name: exchange_name,
        routing_key: routing_key,
        event_payload: {
          event: event.values,
          error: error.message
        }.to_json,
        error_message: error.message
      )
    end
  end
end