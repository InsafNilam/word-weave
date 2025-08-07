#!/usr/bin/env ruby
# frozen_string_literal: true

# Main entry point for Event Service
# Usage: ruby lib/main.rb [command]
# Commands: setup, server, consumer, dead_letter, all

require_relative 'bootstrap'

def show_usage
  puts "Event Service - Microservice for handling events"
  puts ""
  puts "Usage: ruby #{__FILE__} [command]"
  puts ""
  puts "Commands:"
  puts "  setup       - Set up database and run migrations"
  puts "  server      - Start gRPC server"
  puts "  consumer    - Start event consumer"
  puts "  dead_letter - Start dead letter handler"
  puts "  all         - Start all services (includes setup)"
  puts ""
  puts "Environment Variables:"
  puts "  DATABASE_URL     - PostgreSQL connection string (required)"
  puts "  GRPC_PORT        - gRPC server port (default: 50055)"
  puts "  GRPC_HOST        - gRPC server host (default: 0.0.0.0)"
  puts "  LOG_LEVEL        - Logging level (default: INFO)"
  puts "  DEBUG            - Enable debug mode (true/false)"
  puts ""
  puts "Examples:"
  puts "  ruby #{__FILE__} setup"
  puts "  ruby #{__FILE__} server"
  puts "  DATABASE_URL=postgres://user:pass@localhost/mydb ruby #{__FILE__} all"
end

def main
  command = ARGV[0]
  
  case command
  when nil, 'help', '-h', '--help'
    show_usage
    exit(0)
  when 'setup'
    puts "🚀 Starting Event Service Database Setup..."
    EventServiceBootstrap.start_setup
  when 'server'
    puts "🚀 Starting Event Service gRPC Server..."
    EventServiceBootstrap.start_server
  when 'consumer'
    puts "🚀 Starting Event Service Consumer..."
    EventServiceBootstrap.start_consumer
  when 'dead_letter'
    puts "🚀 Starting Event Service Dead Letter Handler..."
    EventServiceBootstrap.start_dead_letter_handler
  when 'all'
    puts "🚀 Starting All Event Service Components..."
    EventServiceBootstrap.start_all_services
  else
    puts "❌ Unknown command: #{command}"
    puts ""
    show_usage
    exit(1)
  end
rescue EventServiceBootstrap::LoadError, EventServiceBootstrap::ServiceError => e
  puts "💥 Service Error: #{e.message}"
  exit(1)
rescue Interrupt
  puts "\n👋 Gracefully shutting down..."
  exit(0)
rescue StandardError => e
  puts "💥 Unexpected Error: #{e.message}"
  puts "📍 Location: #{e.backtrace.first}" if e.backtrace
  
  if ENV['DEBUG'] == 'true'
    puts "\n🐛 Full Stack Trace:"
    puts e.backtrace.join("\n")
  else
    puts "\nℹ️  Run with DEBUG=true for full stack trace"
  end
  
  exit(1)
end

# Run main function if this file is executed directly
main if __FILE__ == $PROGRAM_NAME