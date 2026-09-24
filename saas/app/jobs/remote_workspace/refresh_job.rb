# frozen_string_literal: true

class RemoteWorkspace
  class RefreshJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(remote_workspace)
      remote_workspace.refresh
    end
  end
end
