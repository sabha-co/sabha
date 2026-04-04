# frozen_string_literal: true

class Workspace
  class SnapshotJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(workspace)
      workspace.refresh_snapshot!
    end
  end
end
