require 'cgi'
require 'uri'
require 'yaml'
require 'sequel'
require 'logger'
require 'dotenv/load'
require_relative '../db/setup'

module EventService
  class Configuration
    REQUIRED_ENV_VARS = %w[DATABASE_URL].freeze

    VALID_LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL].freeze
    DEFAULT_PORT_RANGE = 1..65_535

    DEFAULT_VALUES = {
      database_url: 'postgres://localhost:5432/event_db',
      grpc_port: '50055',
      rabbitmq_url: 'amqp://localhost:5672',
      redis_url: 'redis://localhost:6379',
      log_level: 'INFO',
      services: {
        user:   { host: 'user-service', port: 50051 },
        post:   { host: 'post-service', port: 50052 },
        like:   { host: 'like-service', port: 50053 },
        comment:{ host: 'comment-service', port: 50054 },
        event:  { host: 'event-service', port: 50055 },
        media:  { host: 'media-service', port: 50056 }
      }
    }.freeze

    attr_reader :database_url, :rabbitmq_url, :redis_url, :grpc_port, :log_level, :services

    def initialize
      load_environment_variables
      validate_required_configuration
    end

    def database
      @database ||= establish_database_connection
    end

    def db_settings
      @db_settings ||= parse_database_settings
    end

    def logger
      @logger ||= create_logger
    end

    def valid?
      validation_errors.empty?
    end

    def validation_errors
      [].tap do |errors|
        errors << "Invalid database URL" unless valid_database_url?
        errors << "Invalid GRPC port" unless valid_port?(@grpc_port)
        errors << "Invalid log level" unless valid_log_level?(@log_level)
      end
    end

    private

    def load_environment_variables
      @database_url = ENV['DATABASE_URL'] || DEFAULT_VALUES[:database_url]
      @rabbitmq_url = ENV['RABBITMQ_URL'] || DEFAULT_VALUES[:rabbitmq_url]
      @redis_url    = ENV['REDIS_URL']    || DEFAULT_VALUES[:redis_url]
      @grpc_port    = ENV['GRPC_PORT']    || DEFAULT_VALUES[:grpc_port]
      @log_level    = ENV['LOG_LEVEL']    || DEFAULT_VALUES[:log_level]

      @services = {}
      DEFAULT_VALUES[:services].each do |key, defaults|
        @services[key] = {
          host: ENV["#{key.upcase}_SERVICE_HOST"] || defaults[:host],
          port: (ENV["#{key.upcase}_SERVICE_PORT"] || defaults[:port]).to_i
        }
      end
    end

    def validate_required_configuration
      missing_vars = REQUIRED_ENV_VARS.select { |var| ENV[var].nil? || ENV[var].strip.empty? }
      raise ConfigurationError, "Missing required environment variables: #{missing_vars.join(', ')}" unless missing_vars.empty?
    end

    def establish_database_connection
      puts "⏳ Connecting to database at #{masked_database_url}..."

      connection_options = {
        logger: logger,
        test: true,
        connect_timeout: 10,
        pool_timeout: 5,
        max_connections: 10
      }

      db = Sequel.connect(@database_url, connection_options)
      db.test_connection

      puts "✅ Database connection established successfully."
      Sequel::Model.db = db
      db
    rescue Sequel::DatabaseConnectionError => e
      puts "❌ Failed to connect to database: #{e.message}"
      raise DatabaseConnectionError, "Database connection failed: #{e.message}"
    end

    def parse_database_settings
      uri = URI.parse(@database_url)
      {
        adapter:  uri.scheme,
        user:     uri.user || ENV['DB_USER'] || 'postgres',
        password: decode_password(uri.password),
        host:     uri.host || 'localhost',
        port:     uri.port || 5432,
        database: extract_database_name(uri.path)
      }
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid database URL format: #{e.message}"
    end

    def decode_password(raw_password)
      return nil if raw_password.nil?
      CGI.unescape(raw_password)
    rescue
      puts "⚠️  Warning: Failed to decode password, using raw value"
      raw_password
    end

    def extract_database_name(path)
      path&.length.to_i > 1 ? path[1..] : 'event_service'
    end

    def create_logger
      Logger.new($stdout).tap do |log|
        log.level = Logger.const_get(@log_level.upcase) rescue Logger::INFO
        log.formatter = proc do |severity, datetime, _, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
      end
    end

    def valid_database_url?
      URI.parse(@database_url)
      true
    rescue URI::InvalidURIError
      false
    end

    def valid_port?(port)
      DEFAULT_PORT_RANGE.cover?(port.to_i)
    end

    def valid_log_level?(level)
      VALID_LOG_LEVELS.include?(level.upcase)
    end

    def masked_database_url
      uri = URI.parse(@database_url)
      uri.password = '*' * 8 if uri.password
      uri.to_s
    rescue URI::InvalidURIError
      '[INVALID URL]'
    end
  end

  class ConfigurationError < StandardError; end
  class DatabaseConnectionError < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset_configuration!
      @configuration = nil
    end
  end

  def self.initialize!
    DatabaseSetup.new.run
    configuration.database
  end
end