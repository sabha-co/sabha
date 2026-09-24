# Profile → Sign-in methods: connect or disconnect "Continue with sabha.co"
class Users::HubLinksController < ApplicationController
  before_action :require_hub
  before_action :require_unlinked, only: %i[ new create ]
  before_action :require_fresh_session, only: :create

  def new
  end

  # The callback links whoever is signed in when sabha.co answers, so the
  # request is only honoured for a few minutes.
  def create
    session[:hub_link_requested_at] = Time.current.to_i
    redirect_to hub_handshake_url
  end

  def destroy
    Current.user.unlink_hub!
    redirect_to user_profile_url, notice: "sabha.co is disconnected. Sign in the usual way from now on."
  rescue User::HubLinkable::LastSignInMethodError
    redirect_to user_profile_url, alert: "Set a password before disconnecting sabha.co, so you can still sign in."
  end

  private
    def require_hub
      head :not_found unless Sso::Provider.hub.configured?
    end

    def require_unlinked
      redirect_to user_profile_url if Current.user.hub_linked?
    end

    def require_fresh_session
      redirect_to new_user_hub_link_url unless Current.session&.fresh?
    end
end
