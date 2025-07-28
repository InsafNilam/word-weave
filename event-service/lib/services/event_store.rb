require 'json'
require 'concurrent'

module EventService
  class EventStore
    include Concurrent::Async

    attr_reader :db, :logger

    def initialize(db: nil, logger: nil)
      @db = db
      @logger = logger || EventService.configuration.logger
      super()
    end

    def db
      @db ||= EventService.configuration.database
    end

    def store_event(aggregate_id:, aggregate_type:, event_type:, event_data:, 
                   metadata: nil, correlation_id: nil, causation_id: nil)
      validate_input!(aggregate_id, aggregate_type, event_type, event_data)
      
      db.transaction do
        version = next_version(aggregate_id, aggregate_type)
        
        event = Event.create(
          aggregate_id: aggregate_id,
          aggregate_type: aggregate_type,
          event_type: event_type,
          event_data: event_data.to_json,
          metadata: metadata&.to_json,
          version: version,
          correlation_id: correlation_id,
          causation_id: causation_id
        )
        
        logger.info("Event stored: #{event.id} for #{aggregate_type}:#{aggregate_id}")
        event
      end
    rescue => e
      logger.error("Failed to store event: #{e.message}")
      raise e
    end

    def get_events(aggregate_id:, aggregate_type:, from_version: 1)
      Event.by_aggregate(aggregate_id, aggregate_type, from_version: from_version).all
    rescue => e
      logger.error("Failed to get events: #{e.message}")
      []
    end

    def get_events_by_type(event_type:, limit: 100, offset: 0)
      Event.by_type(event_type).recent(limit: limit, offset: offset).all
    rescue => e
      logger.error("Failed to get events by type: #{e.message}")
      []
    end

    def get_recent_events(limit: 100, offset: 0)
      Event.recent(limit: limit, offset: offset).all
    rescue => e
      logger.error("Failed to get recent events: #{e.message}")
      []
    end

    def rebuild_aggregate(aggregate_id, aggregate_type)
      events = get_events(aggregate_id: aggregate_id, aggregate_type: aggregate_type)
      
      aggregate_state = {}
      events.each do |event|
        aggregate_state = apply_event(aggregate_state, event)
      end
      
      aggregate_state
    rescue => e
      logger.error("Failed to rebuild aggregate: #{e.message}")
      {}
    end

    def get_aggregate_version(aggregate_id, aggregate_type)
      Event.where(
        aggregate_id: aggregate_id,
        aggregate_type: aggregate_type
      ).max(:version) || 0
    end

    private

    def validate_input!(aggregate_id, aggregate_type, event_type, event_data)
      validator = EventValidator.new
      result = validator.call(
        aggregate_id: aggregate_id,
        aggregate_type: aggregate_type,
        event_type: event_type,
        event_data: event_data.to_json
      )
      
      raise ArgumentError, result.errors.to_h.inspect unless result.success?
    end

    def next_version(aggregate_id, aggregate_type)
      get_aggregate_version(aggregate_id, aggregate_type) + 1
    end

    def apply_event(state, event)
      case event.event_type
      when 'user.created'
        state.merge(event.event_data_json)
      when 'user.updated'
        state.merge(event.event_data_json)
      when 'user.deleted'
        state.merge(deleted: true, deleted_at: event.timestamp)
      when 'post.created'
        state.merge(event.event_data_json)
      when 'post.updated'
        state.merge(event.event_data_json)
      when 'post.deleted'
        state.merge(deleted: true, deleted_at: event.timestamp)
      when 'comment.created'
        state.merge(event.event_data_json)
      when 'comment.updated'
        state.merge(event.event_data_json)
      when 'comment.deleted'
        state.merge(deleted: true, deleted_at: event.timestamp)
      when 'like.added'
        likes = state[:likes] || []
        likes << event.event_data_json
        state.merge(likes: likes)
      when 'like.removed'
        likes = state[:likes] || []
        like_data = event.event_data_json
        likes.reject! { |like| like['id'] == like_data['id'] }
        state.merge(likes: likes)
      else
        state
      end
    end
  end
end