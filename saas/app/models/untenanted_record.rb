# frozen_string_literal: true

class UntenantedRecord < ActiveRecord::Base
  # Base class for models stored in the untenanted database
  #
  # These models are shared across all workspaces:
  # - GlobalIdentity (cross-workspace authentication)
  # - GlobalSession (cross-workspace sessions)
  # - Workspace (workspace registry)
  # - WorkspaceMembership (links GlobalIdentity to workspaces)
  # - AuthCode (OTP codes for authentication)

  self.abstract_class = true

  connects_to database: { writing: :untenanted, reading: :untenanted }
end
