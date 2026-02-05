# frozen_string_literal: true

# ApplicationRecord Tenanting Configuration
#
# The `tenanted` macro is called directly in app/models/application_record.rb:
#
#   tenanted if defined?(ActiveRecord::Tenanted) && Campfire.saas?
#
# This approach ensures the macro is called at the right time (when ApplicationRecord
# is first loaded) rather than via initializers which have timing issues.

return unless defined?(ActiveRecord::Tenanted) && Campfire.saas?

# Explicitly configure the connection class for gem integrations.
# This tells the gem which abstract base class is tenanted, enabling:
# - Active Job tenant context
# - Action Cable tenant resolution
# - Active Storage tenant prefixing
# - Test framework tenant setup
#
# Default is "ApplicationRecord" but explicit configuration is recommended
# per the activerecord-tenanted guide.
Rails.application.config.active_record_tenanted.connection_class = "ApplicationRecord"
