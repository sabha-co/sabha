# frozen_string_literal: true

module RemoteWorkspacesHelper
  def remote_workspace_lookup_message(error)
    case error
    when RemoteWorkspace::Origin::Invalid then "#{error.message}."
    when RemoteWorkspace::Probe::NotSabha then "That address isn't a Sabha community, or it runs a version of Sabha too old to add. Ask its admin to update Sabha."
    when RemoteWorkspace::Probe::UnsupportedProtocol then "That community runs a version of Sabha this one can't talk to. One of them needs to update Sabha."
    else "We couldn't reach that address. Check it, or try again later."
    end
  end
end
