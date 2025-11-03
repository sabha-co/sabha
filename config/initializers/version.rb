Rails.application.config.app_version = ENV.fetch("APP_VERSION", "0")
Rails.application.config.git_revision = ENV["GIT_REVISION"]
