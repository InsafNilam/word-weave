require 'pg'
require 'sequel'
require 'logger'
require 'dotenv/load'
require 'timeout'

class DatabaseSetup
  MAX_RETRIES = 3
  RETRY_DELAY = 2
  CONNECTION_TIMEOUT = 10
  OPERATION_TIMEOUT = 30

  def initialize(config = EventService.configuration)
    @config = config
    @db_settings = config.db_settings
    @logger = config.logger
    @operations_log = []
  end

  def run
    start_time = Time.now
    
    puts "🛠️  Setting up Event Service Database..."
    log_operation_start("Database Setup")
    
    perform_setup_steps
    
    duration = Time.now - start_time
    log_operation_complete("Database Setup")
    log_success "🎉 Database setup completed successfully in #{duration.round(2)}s!"
    log_operation_summary
    
  rescue => e
    log_operation_failed("Database Setup")
    handle_setup_failure(e)
    exit 1
  end

  private

  def perform_setup_steps
    log_step_start("Configuration Validation")
    validate_configuration
    log_step_complete("Configuration Validation")
    
    log_step_start("Prerequisites Check")
    check_prerequisites
    log_step_complete("Prerequisites Check")
    
    log_step_start("Database Setup")
    setup_database
    log_step_complete("Database Setup")
    
    log_step_start("Migrations")
    run_migrations
    log_step_complete("Migrations")
  end

  def validate_configuration
    log_info "Validating configuration..."
    
    unless @config.valid?
      errors = @config.validation_errors
      log_error "Configuration validation failed:"
      errors.each { |error| log_error "  - #{error}" }
      raise ConfigurationError, "Invalid configuration: #{errors.join(', ')}"
    end
    
    validate_database_settings
    log_success "Configuration validated successfully."
  end

  def validate_database_settings
    required_settings = [:host, :user, :password, :database]
    missing = required_settings.select { |key| @db_settings[key].nil? || @db_settings[key].to_s.strip.empty? }
    
    unless missing.empty?
      raise ConfigurationError, "Missing required database settings: #{missing.join(', ')}"
    end
  end

  def check_prerequisites
    log_info "Checking prerequisites..."
    
    check_postgresql_service
    check_network_connectivity
    check_permissions
    
    log_success "Prerequisites check completed."
  end

  def check_postgresql_service
    log_info "Checking PostgreSQL service availability..."
    
    with_timeout(OPERATION_TIMEOUT, "PostgreSQL service check") do
      with_retry("PostgreSQL service check") do
        connection = create_admin_connection
        result = connection.exec("SELECT version();")
        version = result.first['version']
        log_success "PostgreSQL service is running (#{version.split(' ')[0..1].join(' ')})"
        connection.close
      end
    end
  end

  def check_network_connectivity
    log_info "Testing network connectivity to database host..."
    
    require 'socket'
    
    begin
      with_timeout(5, "Network connectivity check") do
        TCPSocket.new(@db_settings[:host], @db_settings[:port] || 5432).close
        log_success "Network connectivity to #{@db_settings[:host]}:#{@db_settings[:port] || 5432} confirmed."
      end
    rescue => e
      raise NetworkError, "Cannot connect to #{@db_settings[:host]}:#{@db_settings[:port] || 5432} - #{e.message}"
    end
  end

  def check_permissions
    log_info "Checking database permissions..."
    
    with_retry("Permission check") do
      connection = create_admin_connection
      
      # Check if user can create databases
      result = connection.exec("SELECT rolcreatedb FROM pg_roles WHERE rolname = $1", [@db_settings[:user]])
      
      if result.ntuples == 0
        raise PermissionError, "User '#{@db_settings[:user]}' does not exist"
      end
      
      can_create_db = result.first['rolcreatedb'] == 't'
      
      unless can_create_db
        log_warning "User '#{@db_settings[:user]}' cannot create databases. Database must exist or be created by a superuser."
      else
        log_success "User '#{@db_settings[:user]}' has sufficient permissions."
      end
      
      connection.close
    end
  end

  def setup_database
    log_info "Setting up database..."
    
    if database_exists?
      log_success "Database '#{@db_settings[:database]}' already exists."
      check_database_accessibility
    else
      log_warning "Database '#{@db_settings[:database]}' not found."
      create_database
      log_success "Database setup completed."
    end
  end

  def database_exists?
    with_retry("Database existence check") do
      connection = create_target_connection
      connection.close
      true
    end
  rescue DatabaseOperationError
    false
  end

  def check_database_accessibility
    log_info "Verifying database accessibility..."
    
    with_retry("Database accessibility check") do
      connection = create_target_connection
      
      # Test basic operations
      connection.exec("SELECT 1 as test;")
      connection.exec("SELECT current_user, current_database();")
      
      log_success "Database is accessible and operational."
      connection.close
    end
  end

  def create_database
    log_info "Creating database '#{@db_settings[:database]}'..."
    
    with_retry("Database creation") do
      connection = create_admin_connection
      
      begin
        # Use parameterized query for safety
        database_name = connection.escape_identifier(@db_settings[:database])
        owner = connection.escape_identifier(@db_settings[:user])
        
        create_sql = "CREATE DATABASE #{database_name} OWNER #{owner}"
        connection.exec(create_sql)
        
        log_success "Database '#{@db_settings[:database]}' created successfully."
      rescue PG::DuplicateDatabase
        log_warning "Database '#{@db_settings[:database]}' already exists (created by another process)."
      ensure
        connection.close
      end
    end
  end

  def run_migrations
    migrations_dir = File.expand_path('db/migrations')
    
    unless Dir.exist?(migrations_dir)
      log_warning "Migrations directory '#{migrations_dir}' not found. Skipping migrations."
      return
    end

    migration_files = Dir.glob(File.join(migrations_dir, "*.rb")).sort
    
    if migration_files.empty?
      log_warning "No migration files found in '#{migrations_dir}'. Skipping migrations."
      return
    end

    log_info "Found #{migration_files.size} migration file(s). Running migrations..."
    
    begin
      db = @config.database
      log_info "Connected to database for migrations."
      
      # Ensure migrations table exists
      ensure_migrations_table(db)
      
      Sequel.extension :migration
      Sequel::Migrator.run(db, migrations_dir, use_transactions: true)
      
      log_success "All migrations completed successfully."
    rescue Sequel::Error => e
      raise MigrationError, "Migration failed: #{e.message}"
    end
  end

  def ensure_migrations_table(db)
    return if db.table_exists?(:schema_migrations)
    
    log_info "Creating schema_migrations table..."
    db.create_table :schema_migrations do
      String :filename, null: false, primary_key: true
      DateTime :applied_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  def create_admin_connection
    create_postgres_connection('postgres')
  end

  def create_target_connection
    create_postgres_connection(@db_settings[:database])
  end

  def create_postgres_connection(database_name)
    connection_params = build_connection_params(database_name)
    
    connection = PG::Connection.open(connection_params)
    
    # Set connection parameters for better reliability
    connection.exec("SET statement_timeout = '30s'")
    connection.exec("SET lock_timeout = '10s'")
    
    connection
  rescue PG::ConnectionBad, PG::UnableToSend => e
    handle_connection_error(e)
  rescue PG::Error => e
    raise DatabaseOperationError, "Database connection failed: #{e.message}"
  end

  def build_connection_params(database_name)
    {
      dbname: database_name,
      user: @db_settings[:user],
      password: @db_settings[:password],
      host: @db_settings[:host],
      port: @db_settings[:port] || 5432,
      connect_timeout: CONNECTION_TIMEOUT,
      keepalives_idle: 600,
      keepalives_interval: 30,
      keepalives_count: 3,
      application_name: 'EventService-DatabaseSetup'
    }
  end

  def handle_connection_error(error)
    if windows_socket_error?(error)
      raise WindowsSocketError, "Windows socket error: #{error.message}"
    else
      raise DatabaseOperationError, "Connection failed: #{error.message}"
    end
  end

  def with_retry(operation_name, max_retries: MAX_RETRIES)
    retry_count = 0
    
    begin
      yield
    rescue WindowsSocketError => e
      retry_count += 1
      
      if retry_count <= max_retries
        wait_time = RETRY_DELAY * retry_count # Exponential backoff
        log_warning "Windows socket error during #{operation_name} (attempt #{retry_count}/#{max_retries}). Retrying in #{wait_time}s..."
        sleep wait_time
        retry
      else
        log_error "#{operation_name} failed after #{max_retries} retries due to Windows socket errors."
        log_error "💡 Try restarting the PostgreSQL service if socket errors persist."
        raise DatabaseOperationError, "#{operation_name} failed after #{max_retries} retries: #{e.message}"
      end
    rescue DatabaseOperationError, NetworkError, PermissionError, ConfigurationError, MigrationError, VerificationError => e
      # Don't retry these specific errors
      raise e
    rescue => e
      retry_count += 1
      
      if retry_count <= max_retries
        wait_time = RETRY_DELAY * retry_count
        log_warning "Error during #{operation_name} (attempt #{retry_count}/#{max_retries}): #{e.message}. Retrying in #{wait_time}s..."
        sleep wait_time
        retry
      else
        raise DatabaseOperationError, "#{operation_name} failed after #{max_retries} retries: #{e.message}"
      end
    end
  end

  def with_timeout(seconds, operation_name)
    Timeout::timeout(seconds) do
      yield
    end
  rescue Timeout::Error
    raise DatabaseOperationError, "#{operation_name} timed out after #{seconds} seconds"
  end

  def windows_socket_error?(error)
    error.message.match?(/WSAEventSelect|10038|10054|10061/)
  end

  def debug_mode?
    ENV['DEBUG']&.downcase == 'true' || @config.log_level&.upcase == 'DEBUG'
  end

  def handle_setup_failure(error)
    log_error "❌ Setup failed: #{error.class.name} - #{error.message}"
    
    if debug_mode?
      log_debug "Full backtrace:"
      error.backtrace.each { |line| log_debug "  #{line}" }
    end
    
    log_operation_summary
    suggest_troubleshooting_steps(error)
  end

  def suggest_troubleshooting_steps(error)
    puts "\n💡 Troubleshooting suggestions:"
    
    case error
    when NetworkError
      puts "   • Check if PostgreSQL is running on #{@db_settings[:host]}:#{@db_settings[:port] || 5432}"
      puts "   • Verify network connectivity and firewall settings"
    when PermissionError
      puts "   • Ensure the database user has sufficient privileges"
      puts "   • Grant CREATEDB privilege: GRANT CREATEDB TO #{@db_settings[:user]};"
    when ConfigurationError
      puts "   • Check your database configuration settings"
      puts "   • Ensure all required environment variables are set"
    when WindowsSocketError
      puts "   • Restart the PostgreSQL service"
      puts "   • Check Windows firewall settings"
      puts "   • Try running as administrator"
    else
      puts "   • Check PostgreSQL logs for more details"
      puts "   • Verify database server is accessible and running"
      puts "   • Enable DEBUG mode for more detailed logging"
    end
    puts
  end

  def log_operation_start(operation)
    @operations_log << { 
      operation: operation, 
      start_time: Time.now, 
      status: :started,
      steps: []
    }
  end

  def log_operation_complete(operation)
    op = @operations_log.find { |o| o[:operation] == operation }
    if op
      op[:status] = :completed
      op[:end_time] = Time.now
    end
  end

  def log_operation_failed(operation)
    op = @operations_log.find { |o| o[:operation] == operation }
    if op
      op[:status] = :failed
      op[:end_time] = Time.now
    end
  end

  def log_step_start(step_name)
    main_op = @operations_log.last
    if main_op
      main_op[:steps] << {
        name: step_name,
        start_time: Time.now,
        status: :started
      }
    end
  end

  def log_step_complete(step_name)
    main_op = @operations_log.last
    if main_op
      step = main_op[:steps].find { |s| s[:name] == step_name }
      if step
        step[:status] = :completed
        step[:end_time] = Time.now
      end
    end
  end

  def log_step_failed(step_name)
    main_op = @operations_log.last
    if main_op
      step = main_op[:steps].find { |s| s[:name] == step_name }
      if step
        step[:status] = :failed
        step[:end_time] = Time.now
      end
    end
  end

  def log_operation_summary
    return if @operations_log.empty?
    
    puts "\n📊 Operation Summary:"
    @operations_log.each do |op|
      duration = op[:end_time] ? (op[:end_time] - op[:start_time]).round(2) : "incomplete"
      status_icon = case op[:status]
                   when :completed then "✅"
                   when :failed then "❌"
                   else "⏳"
                   end
      puts "   #{status_icon} #{op[:operation]}: #{duration}s"
      
      # Show step details if any steps failed or in debug mode
      if op[:steps]&.any? { |s| s[:status] == :failed } || debug_mode?
        op[:steps]&.each do |step|
          step_duration = step[:end_time] ? (step[:end_time] - step[:start_time]).round(2) : "incomplete"
          step_icon = case step[:status]
                     when :completed then "  ✓"
                     when :failed then "  ✗"
                     else "  ⏳"
                     end
          puts "     #{step_icon} #{step[:name]}: #{step_duration}s"
        end
      end
    end
  end

  # Enhanced logging helpers with operation tracking
  def log_info(message)
    puts "ℹ️  #{message}"
    @logger&.info(message)
  end

  def log_success(message)
    puts "✅ #{message}"
    @logger&.info(message)
  end

  def log_warning(message)
    puts "⚠️  #{message}"
    @logger&.warn(message)
  end

  def log_error(message)
    puts "❌ #{message}"
    @logger&.error(message)
  end

  def log_debug(message)
    puts "🐛 #{message}" if debug_mode?
    @logger&.debug(message)
  end
end

# Enhanced exception classes with better context
class DatabaseOperationError < StandardError
  attr_reader :operation, :details
  
  def initialize(message, operation: nil, details: {})
    super(message)
    @operation = operation
    @details = details
  end
end

class WindowsSocketError < DatabaseOperationError; end
class NetworkError < DatabaseOperationError; end
class PermissionError < DatabaseOperationError; end
class ConfigurationError < DatabaseOperationError; end
class MigrationError < DatabaseOperationError; end
class VerificationError < DatabaseOperationError; end