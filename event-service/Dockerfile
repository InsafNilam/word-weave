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

RUN apk add --no-cache postgresql-client tzdata && rm -rf /var/cache/apk/*

RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

COPY Gemfile Gemfile.lock ./
COPY --from=builder /app/vendor /app/vendor

RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test'

COPY . .

RUN find . -type f -name "*.rb" -o -name "bin/*" | xargs sed -i 's/\r$//' 2>/dev/null || true
RUN chmod +x bin/* 2>/dev/null || true
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 50055

CMD ["bundle", "exec", "ruby", "lib/main.rb", "server"]