json.protocol_major Desktop::PROTOCOL_MAJOR

if Sabha.saas?
  json.peers Current.global_identity.active_workspaces_ordered do |workspace|
    json.id workspace.external_id.to_s
    json.name workspace.name
    json.logo_url(workspace.has_logo? ? account_logo_url(size: "small", script_name: workspace.slug) : nil)
    json.workspace_url "#{request.base_url}/#{workspace.slug.to_s.delete_prefix("/")}"
    json.cable_url api_cable_url(wid: workspace.external_id)
  end
else
  json.peers [ Current.account ] do |account|
    json.id "default"
    json.name account.name
    json.logo_url(account.logo.attached? ? account_logo_url(size: "small") : nil)
    json.workspace_url root_url
    json.cable_url api_cable_url
  end
end
