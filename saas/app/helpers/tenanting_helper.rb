# frozen_string_literal: true

module TenantingHelper
  # Generate ActionCable meta tag with workspace ID as query parameter.
  #
  # kamal-proxy routes /cable to AnyCable-Go via path_prefix, so the
  # workspace ID can't be a path prefix (/1000001/cable won't match).
  # Instead: wss://sabha.co/cable?wid=1000002
  def tenanted_action_cable_meta_tag
    workspace_id = request.env["sabha.workspace_id"]
    base_url = ActionCable.server.config.url || "#{request.script_name}/cable"

    tag "meta", name: "action-cable-url", content: "#{base_url}?wid=#{workspace_id}"
  end

  # Expose the workspace path prefix (request.script_name) to JavaScript.
  # Used by frontend code that builds URLs for fetch requests (e.g., unfurl links).
  def workspace_base_path_meta_tag
    tag "meta", name: "base-path", content: request.script_name
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
