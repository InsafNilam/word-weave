# Build stage
FROM ruby:3.2-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache build-base postgresql-dev

# Copy Gemfile first for better caching
COPY Gemfile Gemfile.lock ./

# Configure bundle to install to vendor/bundle for easier copying
RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Production stage
FROM ruby:3.2-alpine AS production

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache postgresql-client postgresql-dev tzdata && \
    rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

# Copy application files first
COPY Gemfile Gemfile.lock ./

# Copy the vendor/bundle directory from builder
COPY --from=builder /app/vendor /app/vendor

# Configure bundle to use the copied gems
RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test'

# Copy application code
COPY . .

# Fix potential line ending issues
RUN find . -type f -name "*.rb" -o -name "bin/*" | xargs sed -i 's/\r$//' 2>/dev/null || true

# Make executables executable
RUN chmod +x bin/* 2>/dev/null || true

# Change ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user  
USER appuser

# Expose gRPC port
EXPOSE 50055

# Default command
CMD ["bundle", "exec", "ruby", "lib/main.rb", "server"]