# frozen_string_literal: true

module RemoteWorkspacesHelper
  def remote_workspace_lookup_message(error)
    case error
    when RemoteWorkspace::Origin::Error then "#{error.message}."
    when GlobalIdentity::RemoteWorkspaceHasSsoClientError then "That workspace already signs in with sabha.co another way."
    when RemoteWorkspace::Probe::NotSabha then "That isn't a Sabha workspace, or its Sabha is too old."
    when RemoteWorkspace::Probe::Hub then "That's sabha.co, not a self-hosted workspace."
    when RemoteWorkspace::Probe::UnsupportedProtocol then "That workspace's Sabha version isn't compatible."
    else "Couldn't reach that address."
    end
  end
end
