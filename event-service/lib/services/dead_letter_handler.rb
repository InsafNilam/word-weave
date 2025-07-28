require 'concurrent'

module EventService
  class DeadLetterHandler
    include Concurrent::Async

    attr_reader :logger, :publisher

    def initialize(logger = nil)
      @logger = logger || EventService.configuration.logger
      @publisher = EventPublisher.new
      @running = false
      super()
    end

    def start
      @running = true
      @publisher.connect
      
      logger.info("Dead letter handler started")
      
      # Start retry processor
      Concurrent::TimerTask.execute(execution_interval: 60) do
        process_retry_queue if @running
      end
    end

    def stop
      @running = false
      @publisher.disconnect
      logger.info("Dead letter handler stopped")
    end

    def process_retry_queue
      dead_letter_events = DeadLetterEvent.pending_retry(max_retries: 3)
      
      dead_letter_events.each do |dle|
        retry_event(dle)
      end
    end

    def retry_event(dead_letter_event)
      return unless should_retry?(dead_letter_event)

      begin
        event_payload = JSON.parse(dead_letter_event.event_payload)
        
        # Attempt to republish the event
        success = republish_event(
          dead_letter_event.exchange_name,
          dead_letter_event.routing_key,
          event_payload
        )

        if success
          logger.info("Successfully retried event: #{dead_letter_event.original_event_id}")
          dead_letter_event.delete
        else
          dead_letter_event.increment_retry!
          logger.warn("Retry failed for event: #{dead_letter_event.original_event_id}, attempt: #{dead_letter_event.retry_count}")
        end
      rescue => e
        logger.error("Error during retry of event #{dead_letter_event.original_event_id}: #{e.message}")
        dead_letter_event.increment_retry!
      end
    end

    def manual_retry(event_id)
      dead_letter_event = DeadLetterEvent.where(original_event_id: event_id).first
      return false unless dead_letter_event

      retry_event(dead_letter_event)
    end

    def purge_old_events(older_than_days: 7)
      cutoff_date = Time.now - (older_than_days * 24 * 60 * 60)
      
      deleted_count = DeadLetterEvent.where { failed_at < cutoff_date }.delete
      
      logger.info("Purged #{deleted_count} old dead letter events")
      deleted_count
    end

    private

    def should_retry?(dead_letter_event)
      dead_letter_event.retry_count < 3 &&
        dead_letter_event.failed_at > (Time.now - 24 * 60 * 60) # Within 24 hours
    end

    def republish_event(exchange_name, routing_key, event_payload)
      exchange = @publisher.channel.exchange(exchange_name, type: :topic, durable: true)
      
      exchange.publish(
        event_payload.to_json,
        routing_key: routing_key,
        persistent: true,
        message_id: event_payload['id'],
        timestamp: event_payload['timestamp']
      )
      
      true
    rescue => e
      logger.error("Failed to republish event: #{e.message}")
      false
    end
  end
end