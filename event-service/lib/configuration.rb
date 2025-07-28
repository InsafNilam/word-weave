require 'cgi'
require 'uri'
require 'yaml'
require 'sequel'
require 'logger'
require 'dotenv/load'

module EventService
  class Configuration
    REQUIRED_ENV_VARS = %w[DATABASE_URL].freeze
    DEFAULT_VALUES = {
      database_url: 'postgres://localhost:5432/event_service',
      rabbitmq_url: 'amqp://localhost:5672',
      redis_url: 'redis://localhost:6379',
      grpc_port: '50051',
      log_level: 'INFO'
    }.freeze

    attr_accessor :database_url, :rabbitmq_url, :redis_url, :grpc_port, :log_level

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
      validate_configuration.empty?
    end

    def validation_errors
      validate_configuration
    end

    private

    def load_environment_variables
      @database_url = ENV['DATABASE_URL'] || DEFAULT_VALUES[:database_url]
      @rabbitmq_url = ENV['RABBITMQ_URL'] || DEFAULT_VALUES[:rabbitmq_url]
      @redis_url = ENV['REDIS_URL'] || DEFAULT_VALUES[:redis_url]
      @grpc_port = ENV['GRPC_PORT'] || DEFAULT_VALUES[:grpc_port]
      @log_level = ENV['LOG_LEVEL'] || DEFAULT_VALUES[:log_level]
    end

    def validate_required_configuration
      missing_vars = REQUIRED_ENV_VARS.select { |var| ENV[var].nil? || ENV[var].strip.empty? }
      
      unless missing_vars.empty?
        raise ConfigurationError, "Missing required environment variables: #{missing_vars.join(', ')}"
      end
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
        adapter: uri.scheme,
        user: uri.user || ENV['DB_USER'] || 'postgres',
        password: decode_password(uri.password),
        host: uri.host || 'localhost',
        port: uri.port || 5432,
        database: extract_database_name(uri.path)
      }
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid database URL format: #{e.message}"
    end

    def decode_password(raw_password)
      return nil if raw_password.nil?
      
      # Handle URL-encoded passwords safely
      begin
        CGI.unescape(raw_password)
      rescue => e
        puts "⚠️  Warning: Failed to decode password, using raw value"
        raw_password
      end
    end

    def extract_database_name(path)
      return 'event_service' if path.nil? || path.length <= 1
      
      path[1..] # Remove leading slash
    end

    def create_logger
      logger = Logger.new($stdout)
      logger.level = Logger.const_get(@log_level.upcase)
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      logger
    rescue NameError
      puts "⚠️  Invalid log level '#{@log_level}', defaulting to INFO"
      logger = Logger.new($stdout)
      logger.level = Logger::INFO
      logger
    end

    def validate_configuration
      errors = []
      
      errors << "Invalid database URL" unless valid_database_url?
      errors << "Invalid GRPC port" unless valid_port?(@grpc_port)
      errors << "Invalid log level" unless valid_log_level?(@log_level)
      
      errors
    end

    def valid_database_url?
      URI.parse(@database_url)
      true
    rescue URI::InvalidURIError
      false
    end

    def valid_port?(port)
      port_num = port.to_i
      port_num > 0 && port_num <= 65535
    end

    def valid_log_level?(level)
      %w[DEBUG INFO WARN ERROR FATAL].include?(level.upcase)
    end

    def masked_database_url
      uri = URI.parse(@database_url)
      if uri.password
        uri.password = '*' * uri.password.length
      end
      uri.to_s
    rescue URI::InvalidURIError
      '[INVALID URL]'
    end
  end

  # Custom exception classes
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
      configuration.database
  end
end