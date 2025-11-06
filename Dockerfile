# syntax = docker/dockerfile:1

# Make sure it matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.5
FROM ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages need to build gems and Node.js for Tailwind
RUN apt-get update -qq && \
    apt-get install -y build-essential git pkg-config curl libyaml-dev libssl-dev && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    gem install thruster

COPY . .

# Install Node dependencies and build Tailwind CSS
RUN npm install && \
    npx @tailwindcss/cli -i app/assets/stylesheets/application.tailwind.css -o app/assets/builds/tailwind.css

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN mkdir -p /rails/storage/logs
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Configure environment defaults
ENV HTTP_IDLE_TIMEOUT=60 \
    HTTP_READ_TIMEOUT=300 \
    HTTP_WRITE_TIMEOUT=300

# Install packages needed to run the application
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    libsqlite3-0 libvips curl ffmpeg redis git sqlite3 awscli cron nano dialog \
    libjemalloc2 libyaml-0-2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Enable jemalloc for memory optimization (20-40% reduction)
# Create architecture-agnostic symlink for jemalloc (works on both x86_64 and aarch64)
RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so

# Create app user with UID 1000
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built artifacts: gems, application
COPY --from=build --chown=1000:1000 /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=1000:1000 /rails /rails

# Copy cron scripts (before switching to rails user)
COPY script/admin/full-backup /etc/cron.daily/
COPY script/admin/db-backup /etc/cron.hourly/

# Set version and revision
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

# Switch to rails user
USER 1000:1000

# Expose app ports
EXPOSE 3000

# Add health check to verify the application is running
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1

# Start the server by default, this can be overwritten at runtime
CMD ["sh", "-c", "service cron start && bin/configure && bin/boot"]