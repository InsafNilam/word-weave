require 'grpc'
require_relative 'eventpb/event_services_pb'

module EventService
  class GrpcServer < ::Event::EventService::Service
    def initialize
      @event_store = EventStore.new
      @publisher = EventPublisher.new
      @publisher.connect
      @logger = EventService.configuration.logger
    end

    def publish_event(request, _call)
      begin
        # Validate the request
        validator = EventValidator.new
        validation_result = validator.call(
          aggregate_id: request.aggregate_id,
          aggregate_type: request.aggregate_type,
          event_type: request.event_type,
          event_data: request.event_data
        )

        unless validation_result.success?
          return PublishEventResponse.new(
            success: false,
            message: "Validation failed: #{validation_result.errors.to_h}"
          )
        end

        # Parse event data and metadata
        event_data = JSON.parse(request.event_data)
        metadata = request.metadata.empty? ? {} : JSON.parse(request.metadata)

        # Publish the domain event (stores and publishes)
        event = @publisher.publish_domain_event(
          aggregate_id: request.aggregate_id,
          aggregate_type: request.aggregate_type,
          event_type: request.event_type,
          event_data: event_data,
          metadata: metadata,
          correlation_id: request.correlation_id,
          causation_id: request.causation_id
        )

        PublishEventResponse.new(
          event_id: event.id,
          success: true,
          message: "Event published successfully"
        )
      rescue JSON::ParserError => e
        PublishEventResponse.new(
          success: false,
          message: "Invalid JSON: #{e.message}"
        )
      rescue => e
        @logger.error("Error publishing event: #{e.message}")
        PublishEventResponse.new(
          success: false,
          message: "Internal error: #{e.message}"
        )
      end
    end

    def get_events(request, _call)
      begin
        events = if request.aggregate_type.empty? && request.event_type.empty?
                   @event_store.get_recent_events(
                     limit: request.limit > 0 ? request.limit : 100,
                     offset: request.offset
                   )
                 elsif !request.event_type.empty?
                   @event_store.get_events_by_type(
                     event_type: request.event_type,
                     limit: request.limit > 0 ? request.limit : 100,
                     offset: request.offset
                   )
                 else
                   []
                 end

        grpc_events = events.map { |event| event_to_grpc(event) }

        GetEventsResponse.new(
          events: grpc_events,
          success: true,
          message: "Events retrieved successfully"
        )
      rescue => e
        @logger.error("Error getting events: #{e.message}")
        GetEventsResponse.new(
          events: [],
          success: false,
          message: "Internal error: #{e.message}"
        )
      end
    end

    def get_events_by_aggregate(request, _call)
      begin
        events = @event_store.get_events(
          aggregate_id: request.aggregate_id,
          aggregate_type: request.aggregate_type,
          from_version: request.from_version > 0 ? request.from_version : 1
        )

        grpc_events = events.map { |event| event_to_grpc(event) }

        GetEventsResponse.new(
          events: grpc_events,
          success: true,
          message: "Events retrieved successfully"
        )
      rescue => e
        @logger.error("Error getting events by aggregate: #{e.message}")
        GetEventsResponse.new(
          events: [],
          success: false,
          message: "Internal error: #{e.message}"
        )
      end
    end

    def subscribe_to_events(request, _call)
      begin
        subscription_id = EventSubscription.create(
          consumer_group: request.consumer_group,
          event_types_array: request.event_types,
          callback_url: request.callback_url,
          status: 'active'
        ).id

        SubscribeToEventsResponse.new(
          subscription_id: subscription_id,
          success: true,
          message: "Subscription created successfully"
        )
      rescue => e
        @logger.error("Error creating subscription: #{e.message}")
        SubscribeToEventsResponse.new(
          success: false,
          message: "Internal error: #{e.message}"
        )
      end
    end

    private

    def event_to_grpc(event)
      Event.new(
        id: event.id,
        aggregate_id: event.aggregate_id,
        aggregate_type: event.aggregate_type,
        event_type: event.event_type,
        event_data: event.event_data,
        metadata: event.metadata || '',
        version: event.version,
        timestamp: event.timestamp,
        correlation_id: event.correlation_id || '',
        causation_id: event.causation_id || ''
      )
    end
  end
end