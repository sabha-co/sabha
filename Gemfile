source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Rails
gem "rails", github: "rails/rails", ref: "cfa4e1b475472c7980a42dd810f237951db5108a"
gem "bootsnap", require: false

# Drivers
gem "sqlite3", ">= 2.9"
gem "redis", "~> 5.4"

# Deployment
gem "puma", "~> 8.0"
gem "thruster"

# Jobs
gem "solid_queue"

# Assets
gem "propshaft"
gem "importmap-rails"

# Hotwire
gem "turbo-rails"
gem "stimulus-rails"

# Rich text
gem "lexxy"

# Real-time WebSocket server (core gem avoids gRPC dependency since we use HTTP RPC mode)
# Sourced from our fork for the presence-leave id string-cast fix, until it ships upstream.
gem "anycable-rails-core", github: "ashwin47/anycable-rails", branch: "presence-leave-cast-id"

# Media handling
gem "image_processing", ">= 1.2"
# image_processing 2.0 made the libvips backend a soft dependency. ActiveStorage's
# default :vips variant processor loads it on demand, so require: false keeps boot
# from depending on the native libvips library being present.
gem "ruby-vips", "~> 2.0", require: false

# Email
gem "resend"

# Telemetry
gem "sentry-ruby"
gem "sentry-rails"

# Profiling
gem "rack-mini-profiler", "~> 4.0", require: false
gem "stackprof", "~> 0.2"

# Metrics — non-production only. /metrics (Prometheus) is mounted in the
# performance/development envs (see config/routes.rb); these load only in the
# :performance / :development bundler groups, so production carries no overhead.
group :development, :performance do
  gem "yabeda"
  gem "yabeda-prometheus"
  gem "yabeda-activerecord"   # AR connection-pool + query metrics
  gem "yabeda-puma-plugin"    # Puma thread-pool metrics (see config/puma.rb)
  # GVL: yabeda-gvl_metrics 0.2.0 tags gauges with `pid`, which prometheus-client
  # 4.x reserves (boot crash). Deferred until a compatible GVL source is wired.
end

# Other
gem "bcrypt"
gem "msgpack", ">= 1.8.0"
gem "web-push"
gem "surfguard", "~> 0.2.0" # SSRF address policy behind outbound fetch/webhook/push
gem "rqrcode"
gem "rails_autolink"
gem "geared_pagination"
gem "jbuilder"
gem "net-http-persistent"
gem "kredis"
gem "platform_agent"
gem "faraday"
gem "rubyzip", require: "zip"
gem "rails_cloudflare_turnstile"

group :development, :test do
  gem "debug"
  gem "benchmark"
  gem "rubocop-rails-omakase", require: false
  gem "faker", require: false
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "dotenv"
end

group :development do
  gem "letter_opener"
  gem "lefthook", "~> 2.0"
end

group :test do
  gem "capybara"
  gem "cuprite"
  gem "mocha"
  gem "test-prof"
  gem "webmock", require: false
end
