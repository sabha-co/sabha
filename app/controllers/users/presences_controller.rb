# Per-user presence picked in the sidebar profile flyout. Always operates on
# the current user; the :user_id route param is hard-coded to "me" so URLs are
# stable across views (matching push_subscriptions, profile, etc.). The flyout
# buttons apply the choice optimistically and answer head :ok — nothing
# broadcasts (design v2.1: roster presence stays connection-derived).
class Users::PresencesController < ApplicationController
  def update
    status = params.require(:status)
    return head :unprocessable_entity unless User::PRESENCE_OPTIONS.include?(status)

    Current.user.update!(presence: status)
    head :ok
  end
end
