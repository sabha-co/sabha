source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Rails
gem "rails", github: "rails/rails", branch: "main"

# Drivers
gem "sqlite3", ">= 2.9"
gem "redis", "~> 5.4"

# Deployment
gem "puma", "~> 7.1"
gem "thruster"

# Jobs
gem "solid_queue"

# Assets
gem "propshaft"
gem "importmap-rails"
gem "vite_rails", "~> 3.0"

# Hotwire
gem "turbo-rails"
gem "stimulus-rails"

# Real-time WebSocket server (core gem avoids gRPC dependency since we use HTTP RPC mode)
gem "anycable-rails-core", "~> 1.5"

# Media handling
gem "image_processing", ">= 1.2"

# Email
gem "resend"
gem "mailkick"

# Telemetry
gem "sentry-ruby"
gem "sentry-rails"

# Profiling
gem "rack-mini-profiler", "~> 4.0", require: false
gem "stackprof", "~> 0.2"

# Other
gem "bcrypt"
gem "msgpack", ">= 1.8.0"
gem "web-push"
gem "rqrcode"
gem "rails_autolink"
gem "geared_pagination"
gem "jbuilder"
gem "net-http-persistent"
gem "kredis"
gem "platform_agent"
gem "faraday"
gem "rubyzip", require: "zip"

group :development, :test do
  gem "debug"
  gem "rubocop-rails-omakase", require: false
  gem "faker", require: false
  gem "brakeman", require: false
  gem "dotenv"
end

group :development do
  gem "letter_opener"
  gem "lefthook", "~> 2.0"
end

group :test do
  gem "capybara"
  gem "mocha"
  gem "selenium-webdriver"
  gem "webmock", require: false
end
