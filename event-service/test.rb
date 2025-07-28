require 'pg'
require 'uri'
require 'cgi' # For unescaping, as we discussed

DATABASE_URL = "postgres://postgres:47%40n2EEr@127.0.0.1:5432/event_service" # Use 127.0.0.1 explicitly

begin
  uri = URI.parse(DATABASE_URL)
  raw_password = uri.password || ENV['DB_PASSWORD']
  decoded_password = raw_password ? CGI.unescape(raw_password) : nil

  conn_params = {
    host: uri.host,
    port: uri.port,
    user: uri.user,
    password: decoded_password,
    dbname: uri.path[1..] || 'event_service'
  }

  puts "Attempting to connect to PostgreSQL with parameters:"
  puts "  Host: #{conn_params[:host]}"
  puts "  Port: #{conn_params[:port]}"
  puts "  User: #{conn_params[:user]}"
  puts "  Password: #{conn_params[:password].nil? ? '[nil]' : '[present]'}" # Don't print actual password
  puts "  DB Name: #{conn_params[:dbname]}"

  conn = PG.connect(conn_params)
  puts "✅ Successfully connected to PostgreSQL!"
  puts "PostgreSQL Server Version: #{conn.server_version}"

  # Test a simple query
  res = conn.exec("SELECT 1 + 1 AS two;")
  puts "Query Result: #{res[0]['two']}"

  # If you want to try creating the database, you can modify to connect to 'postgres' first:
  # conn.close
  # conn = PG.connect(conn_params.merge(dbname: 'postgres'))
  # puts "Creating database '#{conn_params[:dbname]}'..."
  # conn.exec("CREATE DATABASE #{conn.quote_ident(conn_params[:dbname])}")
  # puts "Database created!"


rescue PG::Error => e
  puts "❌ PostgreSQL Connection Error: #{e.message}"
rescue => e
  puts "❌ An unexpected error occurred: #{e.message}"
ensure
  conn.close if conn
end