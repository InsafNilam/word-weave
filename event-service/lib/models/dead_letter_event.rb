require 'sequel'

module EventService
  class DeadLetterEvent < Sequel::Model
    def before_create
      self.id ||= UUID.generate
      super
    end

    def increment_retry!
      self.retry_count = (retry_count || 0) + 1
      save
    end

    def self.pending_retry(max_retries: 3)
      where { retry_count < max_retries }
    end

    def self.by_exchange(exchange_name)
      where(exchange_name: exchange_name)
    end
  end
end