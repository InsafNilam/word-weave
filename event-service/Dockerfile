FROM ruby:3.2-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache build-base postgresql-dev

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy application code
COPY . .

# Make executables executable
RUN chmod +x bin/*

# Expose gRPC port
EXPOSE 50051

# Default command
CMD ["ruby", "lib/main.rb", "server"]