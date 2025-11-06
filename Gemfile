source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }
git_source(:bc)     { |repo| "https://github.com/basecamp/#{repo}" }

# Rails
gem "rails", "~> 8.0.0"

# Drivers
gem "sqlite3", ">= 2.8"
gem "redis", ">= 5.4"

# Deployment
gem "puma", "~> 7.1"

# Jobs
gem "resque", "~> 2.7.0"
gem "resque-pool", "~> 0.7.1"
gem "resque-scheduler", "~> 4.11.0"

# Assets
gem "propshaft"
gem "importmap-rails"

# Hotwire
gem "turbo-rails"
gem "stimulus-rails"

# Media handling
gem "image_processing", ">= 1.2"

# Telemetry
gem "sentry-ruby"
gem "sentry-rails"

# Other
gem "bcrypt"
gem "msgpack", ">= 1.7.0"
gem "web-push"
gem "rqrcode"
gem "rails_autolink"
gem "geared_pagination"
gem "jbuilder"
gem "net-http-persistent"
gem "kredis"
gem "platform_agent"
gem "thruster"
gem "faraday"

group :development, :test do
  gem "debug"
  gem "rubocop-rails-omakase", require: false
  gem "faker", require: false
  gem "brakeman", require: false
end

group :test do
  gem "capybara"
  gem "mocha"
  gem "selenium-webdriver"
  gem "webmock", require: false
end

gem "dotenv", groups: [ :development, :test ]
gem "letter_opener", group: :development
gem "stringex"
gem "ostruct" # Required by stringex, no longer in default gems as of Ruby 3.5.0

gem "resend"

gem "heapy", group: :development

gem "rufus-scheduler"
gem "mailkick"

gem "rack-mini-profiler", "~> 4.0", require: false
gem "stackprof", "~> 0.2"

gem "inertia_rails", "~> 3.11"

gem "vite_rails", "~> 3.0"
