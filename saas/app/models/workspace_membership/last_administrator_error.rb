# frozen_string_literal: true

class WorkspaceMembership::LastAdministratorError < StandardError
  def message
    "Cannot leave workspace as the last administrator"
  end
end
