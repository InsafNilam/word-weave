require 'sequel'
require 'json'

module EventService
  class EventSubscription < Sequel::Model
    def before_create
      self.id ||= UUID.generate
      super
    end

    def event_types_array
      JSON.parse(event_types) if event_types
    rescue JSON::ParserError
      []
    end

    def event_types_array=(types)
      self.event_types = types.to_json
    end

    def active?
      status == 'active'
    end

    def self.active_subscriptions
      where(status: 'active')
    end
  end
end