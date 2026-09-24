json.protocol_major Sabha::PROTOCOL_MAJOR

if Sabha.saas?
  memberships = Current.global_identity.switcher_memberships
  workspaces, remotes = memberships.partition { it.is_a?(WorkspaceMembership) }

  json.peers workspaces.map(&:workspace) do |workspace|
    json.id workspace.external_id.to_s
    json.name workspace.name
    json.logo_url(workspace.has_logo? ? account_logo_url(size: "small", script_name: workspace.slug) : nil)
    json.workspace_url "#{request.base_url}/#{workspace.slug.to_s.delete_prefix("/")}"
    json.cable_url api_cable_url(wid: workspace.external_id)
  end

  # Self-hosted workspaces from the person's list. A separate key, so a client
  # that only knows workspace peers keeps working.
  json.remote_peers remotes do |membership|
    remote_workspace = membership.remote_workspace
    json.id "remote:#{membership.id}"
    json.origin remote_workspace.origin
    json.name remote_workspace.name
    json.logo_url(remote_workspace.logo? ? remote_workspace_logo_url(remote_workspace, script_name: "") : nil)
    json.unreachable remote_workspace.unreachable?
    json.shortcut remote_workspace.pairing_active?
  end

  # The selector's order across both kinds, as peer ids
  json.order memberships.map { it.is_a?(WorkspaceMembership) ? it.workspace.external_id.to_s : "remote:#{it.id}" }
else
  json.peers [ Current.account ] do |account|
    json.id "default"
    json.name account.name
    json.logo_url(account.logo.attached? ? account_logo_url(size: "small") : nil)
    json.workspace_url root_url
    json.cable_url api_cable_url
  end
end
