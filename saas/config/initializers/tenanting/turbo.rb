# frozen_string_literal: true

# Turbo Broadcasts Tenant Context
#
# Ensures Turbo Stream broadcasts include the workspace prefix (script_name)
# in generated URLs. Without this, broadcast URLs would be missing the
# workspace path prefix (e.g., /1000001).
#
# Pattern adapted from Fizzy's multi-tenant implementation.

return unless Sabha.saas?

module TurboStreamsChannelExtensions
  extend ActiveSupport::Concern

  class_methods do
    def render_format(format, **rendering)
      script_name = resolve_tenant_script_name
      if script_name.present?
        ApplicationController.renderer.new(script_name: script_name).render(formats: [ format ], **rendering)
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
# methods in ApplicationController, separate from the class-method path above).
Rails.application.config.to_prepare do
  ApplicationController.class_eval do
    private

    def render_format(format, **rendering)
      if request.script_name.present?
        ApplicationController.renderer.new(script_name: request.script_name).render(formats: [ format ], **rendering)
      else
        ApplicationController.render(formats: [ format ], **rendering)
      end
    end
  end
end
