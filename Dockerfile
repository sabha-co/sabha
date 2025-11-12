# syntax = docker/dockerfile:1

# Make sure it matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
  BUNDLE_DEPLOYMENT="1" \
  BUNDLE_PATH="/usr/local/bundle" \
  BUNDLE_WITHOUT="development:test" \
  LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages need to build gems and Node.js for Vite
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y \
  build-essential git pkg-config curl libyaml-dev libssl-dev ca-certificates && \
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
  apt-get install --no-install-recommends -y nodejs && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
  bundle clean --force && \
  gem install thruster && \
  gem cleanup

# Copy application code
COPY . .

# Install Node dependencies and build assets with Vite
RUN npm install && \
  npm run build

# Precompile assets
RUN mkdir -p /rails/storage/logs && \
  SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Clean up build artifacts
RUN rm -rf node_modules tmp/cache .git


# Final stage for app image
FROM base

# Install runtime packages
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y \
  curl libsqlite3-0 libvips libjemalloc2 libyaml-0-2 ca-certificates \
  ffmpeg redis-server git sqlite3 awscli cron && \
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Configure environment defaults
ENV HTTP_IDLE_TIMEOUT=60 \
  HTTP_READ_TIMEOUT=300 \
  HTTP_WRITE_TIMEOUT=300

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Copy cron scripts
COPY script/admin/full-backup /etc/cron.daily/
COPY script/admin/db-backup /etc/cron.hourly/

# Set version and revision
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

# Image metadata
ARG OCI_DESCRIPTION
LABEL org.opencontainers.image.description="${OCI_DESCRIPTION}"
ARG OCI_SOURCE
LABEL org.opencontainers.image.source="${OCI_SOURCE}"
LABEL org.opencontainers.image.licenses="MIT"

# Expose app ports
EXPOSE 3000

# Health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start the server
CMD ["sh", "-c", "service cron start && bin/configure && bin/boot"]
