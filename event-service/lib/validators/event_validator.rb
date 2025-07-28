require 'dry-validation'

module EventService
  class EventValidator < Dry::Validation::Contract
    params do
      required(:aggregate_id).filled(:string)
      required(:aggregate_type).filled(:string)
      required(:event_type).filled(:string)
      required(:event_data).filled(:string)
      optional(:metadata).maybe(:string)
      optional(:correlation_id).maybe(:string)
      optional(:causation_id).maybe(:string)
    end

    rule(:aggregate_type) do
      key.failure('must be valid aggregate type') unless Types::AggregateType.valid?(value)
    end

    rule(:event_type) do
      key.failure('must be valid event type') unless Types::EventType.valid?(value)
    end

    rule(:event_data) do
      begin
        JSON.parse(value)
      rescue JSON::ParserError
        key.failure('must be valid JSON')
      end
    end
  end
end