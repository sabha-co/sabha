# frozen_string_literal: true

module Sabha
  module Saas
    # Renders a partial/template under a tenant's workspace prefix.
    #
    # Wraps the call with `ActionText::Content.with_renderer(renderer)` so any
    # ActionText body rendered inside the partial (e.g., a message containing
    # @-mentions) uses the same script_name-aware renderer. Without that wrap,
    # ActionText falls back to its own anonymous renderer with no script_name,
    # producing prefix-less avatar URLs that get baked into broadcast HTML and
    # the fragment cache — which then 404 for everyone.
    module TenantedRendering
      module_function

      def render(script_name, format, **rendering)
        renderer = ApplicationController.renderer.new(script_name: script_name)
        ActionText::Content.with_renderer(renderer) do
          renderer.render(formats: [ format ], **rendering)
        end
      end
    end
  end
end
