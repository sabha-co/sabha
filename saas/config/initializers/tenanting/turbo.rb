# frozen_string_literal: true

# Turbo Broadcasts Tenant Context
#
# Ensures Turbo Stream broadcasts include the workspace prefix (script_name)
# in generated URLs. Without this, broadcast URLs would be missing the
# workspace path prefix (e.g., /1000001).
#
# Pattern adapted from Fizzy's multi-tenant implementation.

return unless Sabha.saas?

require_relative "../../../lib/sabha/saas/tenanted_rendering"

module TurboStreamsChannelExtensions
  extend ActiveSupport::Concern

  class_methods do
    def render_format(format, **rendering)
      script_name = resolve_tenant_script_name
      if script_name.present?
        Sabha::Saas::TenantedRendering.render(script_name, format, **rendering)
      else
        super
      end
    end

    private

    def resolve_tenant_script_name
      # Prefer Current.workspace (available in request context)
      # Fall back to ApplicationRecord.current_tenant (available in job context)
      if Current.workspace.present?
        Current.workspace.slug
      elsif ApplicationRecord.current_tenant.present?
        "/#{ApplicationRecord.current_tenant}"
      end
    end
  end
end

Rails.application.config.after_initialize do
  Turbo::StreamsChannel.prepend TurboStreamsChannelExtensions
end

# Also override the instance-level render_format used when controllers call
# broadcast_replace_to etc. (Turbo::Streams::Broadcasts is included as instance
# methods in ApplicationController, separate from the class-method path above.)
#
# DO NOT replace this with `ActiveSupport.on_load(:action_controller_base)` to
# silence the premature-load-hook warning in Rails 8.2+. Turbo::Streams::Broadcasts
# is `include`d in ApplicationController (see app/controllers/application_controller.rb)
# and defines its own private `render_format` (turbo-rails/app/channels/turbo/streams/
# broadcasts.rb). Attaching the override to ActionController::Base via on_load
# would place it BELOW the included module in MRO — Turbo's default would silently
# win, and tenant-aware rendering would be bypassed for controller-originated
# broadcasts (e.g. broadcast_replace_to in Messages::BookmarksController and
# Rooms::InvolvementsController), producing Turbo Stream URLs without the
# workspace prefix. Tests do not catch this because they don't assert on rendered
# Turbo Stream URL contents under script_name. Defining on ApplicationController
# itself keeps the override above included modules in the lookup chain. The
# trade-off is the one-time boot warning, accepted in exchange for correctness.
Rails.application.config.to_prepare do
  ApplicationController.class_eval do
    private

    def render_format(format, **rendering)
      if request.script_name.present?
        Sabha::Saas::TenantedRendering.render(request.script_name, format, **rendering)
      else
        ApplicationController.render(formats: [ format ], **rendering)
      end
    end
  end
end
