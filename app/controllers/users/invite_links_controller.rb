class Users::InviteLinksController < ApplicationController
  before_action :ensure_can_create_invite_links

  def create
    Current.user.regenerate_invite_link

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("invite_link", partial: "users/profiles/invite_link")
      end
      format.html { redirect_to user_profile_path }
    end
  end

  private

  def ensure_can_create_invite_links
    redirect_to user_profile_path unless Current.account.settings.allow_users_to_create_invite_links?
  end
end
