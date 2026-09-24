# frozen_string_literal: true

class GlobalIdentity
  class JoinDefaultWorkspaceJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(identity)
      identity.join_default_workspace
    end
  end
end
