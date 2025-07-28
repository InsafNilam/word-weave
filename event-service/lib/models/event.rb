require 'sequel'
require 'json'

module EventService
  class Event < Sequel::Model
    def before_create
      self.id ||= UUID.generate
      self.timestamp ||= Time.now.to_i * 1000
      super
    end

    def event_data_json
      JSON.parse(event_data) if event_data
    rescue JSON::ParserError
      {}
    end

    def metadata_json
      JSON.parse(metadata) if metadata
    rescue JSON::ParserError
      {}
    end

    def self.by_aggregate(aggregate_id, aggregate_type, from_version: 1)
      where(
        aggregate_id: aggregate_id,
        aggregate_type: aggregate_type
      ).where { version >= from_version }.order(:version)
    end

    def self.by_type(event_type)
      where(event_type: event_type)
    end

    def self.recent(limit: 100, offset: 0)
      order(Sequel.desc(:timestamp)).limit(limit, offset)
    end
  end
end