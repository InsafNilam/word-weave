require 'dry-types'
require 'dry-struct'

module EventService
  module Types
    include Dry.Types()

    EventType = String.enum(
      'user.created', 'user.updated', 'user.deleted',
      'post.created', 'post.updated', 'post.deleted',
      'comment.created', 'comment.updated', 'comment.deleted',
      'like.added', 'like.removed'
    )

    AggregateType = String.enum('user', 'post', 'comment', 'like')
  end

  class EventStruct < Dry::Struct
    transform_keys(&:to_sym)

    attribute :id, Types::String
    attribute :aggregate_id, Types::String
    attribute :aggregate_type, Types::AggregateType
    attribute :event_type, Types::EventType
    attribute :event_data, Types::String
    attribute :metadata, Types::String.optional
    attribute :version, Types::Integer
    attribute :timestamp, Types::Integer
    attribute :correlation_id, Types::String.optional
    attribute :causation_id, Types::String.optional
  end
end