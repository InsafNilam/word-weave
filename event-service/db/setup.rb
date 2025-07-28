require 'pg'
require 'sequel'
require 'logger'
require 'dotenv/load'

class DatabaseSetup
  MAX_RETRIES = 3
  RETRY_DELAY = 2
  CONNECTION_TIMEOUT = 10

  def initialize(config = EventService.configuration)
    @config = config
    @db_settings = config.db_settings
    @logger = config.logger
  end

  def run
    puts "🛠️  Setting up Event Service Database..."
    
    log_info "Validating configuration..."
    validate_configuration
    
    log_info "Setting up database..."
    setup_database
    
    log_info "Running migrations..."
    run_migrations
    
    puts "🎉 Database setup completed successfully!"
    
  rescue => e
    log_error "Setup failed: #{e.class.name} - #{e.message}"
    log_debug e.backtrace.join("\n") if debug_mode?
    exit 1
  end

  private

  def validate_configuration
    unless @config.valid?
      errors = @config.validation_errors
      log_error "Configuration validation failed:"
      errors.each { |error| log_error "  - #{error}" }
      exit 1
    end
    
    log_success "Configuration validated successfully."
  end

  def setup_database
    log_info "Checking PostgreSQL connection..."
    ensure_postgres_connection
    
    log_info "Checking database existence..."
    if database_exists?
      log_success "Database '#{@db_settings[:database]}' already exists."
    else
      log_warning "Database '#{@db_settings[:database]}' not found."
      create_database
    end
  end

  def ensure_postgres_connection
    with_retry("PostgreSQL connection test") do
      connection = create_postgres_connection('postgres')
      connection.close
      log_success "PostgreSQL connection established."
    end
  end

  def database_exists?
    with_retry("Database existence check") do
      connection = create_postgres_connection(@db_settings[:database])
      connection.close
      true
    end
  rescue DatabaseOperationError
    false
  end

  def create_database
    log_info "Creating database '#{@db_settings[:database]}'..."
    
    with_retry("Database creation") do
      connection = create_postgres_connection('postgres')
      
      begin
        database_name = connection.quote_ident(@db_settings[:database])
        connection.exec("CREATE DATABASE #{database_name}")
        log_success "Database '#{@db_settings[:database]}' created successfully."
      rescue PG::DuplicateDatabase
        log_warning "Database '#{@db_settings[:database]}' already exists."
      ensure
        connection.close
      end
    end
  end

  def run_migrations
    migrations_dir = 'db/migrations'
    
    unless Dir.exist?(migrations_dir)
      log_warning "Migrations directory '#{migrations_dir}' not found. Skipping migrations."
      return
    end

    begin
      db = @config.database
      log_info "Connected to database for migrations."
      
      Sequel.extension :migration
      Sequel::Migrator.run(db, migrations_dir)
      
      log_success "Migrations completed successfully."
    rescue Sequel::Error => e
      raise DatabaseOperationError, "Migration failed: #{e.message}"
    end
  end

  def create_postgres_connection(database_name)
    connection_params = {
      dbname: database_name,
      user: @db_settings[:user],
      password: @db_settings[:password],
      host: @db_settings[:host],
      port: @db_settings[:port] || 5432,
      connect_timeout: CONNECTION_TIMEOUT,
      keepalives_idle: 600,
      keepalives_interval: 30,
      keepalives_count: 3
    }

    PG::Connection.open(connection_params)
  rescue PG::ConnectionBad, PG::UnableToSend => e
    handle_connection_error(e)
  rescue PG::Error => e
    raise DatabaseOperationError, "Database connection failed: #{e.message}"
  end

  def handle_connection_error(error)
    if windows_socket_error?(error)
      raise WindowsSocketError, error.message
    else
      raise DatabaseOperationError, "Connection failed: #{error.message}"
    end
  end

  def with_retry(operation_name)
    retry_count = 0
    
    begin
      yield
    rescue WindowsSocketError => e
      retry_count += 1
      
      if retry_count <= MAX_RETRIES
        log_warning "Windows socket error during #{operation_name} (attempt #{retry_count}/#{MAX_RETRIES}). Retrying in #{RETRY_DELAY}s..."
        sleep RETRY_DELAY
        retry
      else
        log_error "#{operation_name} failed after #{MAX_RETRIES} retries due to Windows socket errors."
        log_error "Try restarting the PostgreSQL service if socket errors persist."
        raise DatabaseOperationError, "#{operation_name} failed: #{e.message}"
      end
    rescue DatabaseOperationError => e
      raise e
    rescue => e
      raise DatabaseOperationError, "#{operation_name} failed: #{e.message}"
    end
  end

  def windows_socket_error?(error)
    error.message.include?("WSAEventSelect") || error.message.include?("10038")
  end

  def debug_mode?
    ENV['DEBUG'] == 'true' || @config.log_level.upcase == 'DEBUG'
  end

  # Logging helpers
  def log_info(message)
    puts "ℹ️  #{message}"
    @logger.info(message)
  end

  def log_success(message)
    puts "✅ #{message}"
    @logger.info(message)
  end

  def log_warning(message)
    puts "⚠️  #{message}"
    @logger.warn(message)
  end

  def log_error(message)
    puts "❌ #{message}"
    @logger.error(message)
  end

  def log_debug(message)
    puts "🐛 #{message}" if debug_mode?
    @logger.debug(message)
  end
end

# Custom exception classes
class DatabaseOperationError < StandardError; end
class WindowsSocketError < StandardError; end