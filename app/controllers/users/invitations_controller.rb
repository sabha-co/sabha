class Users::InvitationsController < ApplicationController
  before_action :ensure_personal_invites_allowed

  def show
  end

  private
    def ensure_personal_invites_allowed
      return if Current.account.settings.allow_users_to_create_invite_links?

      redirect_to user_profile_path
    end
end
