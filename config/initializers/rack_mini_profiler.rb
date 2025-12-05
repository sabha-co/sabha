# frozen_string_literal: true

if Rails.env.development?
  require "rack-mini-profiler"

  Rack::MiniProfilerRails.initialize!(Rails.application)

  # Start hidden by default (press Alt+P to toggle)
  Rack::MiniProfiler.config.start_hidden = false

  # Allow all users in development
  Rack::MiniProfiler.config.authorization_mode = :allow_all
end
