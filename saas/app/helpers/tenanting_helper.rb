# frozen_string_literal: true

module TenantingHelper
  # Generate ActionCable meta tag with workspace prefix in URL
  # This ensures WebSocket connections go through the path rewriter
  # so tenant context is established for channels.
  #
  # Without this: /cable
  # With this:    /1000002/cable
  def tenanted_action_cable_meta_tag
    tag "meta",
        name: "action-cable-url",
        content: "#{request.script_name}#{ActionCable.server.config.mount_path}"
  end

  # Generate a URL without the workspace prefix (script_name)
  # Use this for URLs that should work outside workspace context,
  # like join links which are accessed at the root domain.
  #
  # Example:
  #   Inside workspace 1000002:
  #     join_url(code)           => "http://localhost:3000/1000002/join/abc123"
  #     untenanted_url(:join, code) => "http://localhost:3000/join/abc123"
  #
  def untenanted_url(route_name, *args, **kwargs)
    # Temporarily clear script_name to generate URL without workspace prefix
    url_options = kwargs.merge(script_name: "", host: request.host, port: request.port, protocol: request.protocol)
    Rails.application.routes.url_helpers.public_send(:"#{route_name}_url", *args, **url_options)
  end

  def untenanted_path(route_name, *args, **kwargs)
    # Generate path without workspace prefix
    url_options = kwargs.merge(script_name: "")
    Rails.application.routes.url_helpers.public_send(:"#{route_name}_path", *args, **url_options)
  end
end
