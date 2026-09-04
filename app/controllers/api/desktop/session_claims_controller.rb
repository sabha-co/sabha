class API::Desktop::SessionClaimsController < ApplicationController
  skip_forgery_protection
  include DesktopClientDetection

  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }

  def create
    claim = redeem_claim!
    establish_session_from_claim!(claim)
    render json: { return_path: claim.return_path }
  rescue Desktop::SessionClaim::Error, Desktop::GlobalSessionClaim::Error
    render json: { error: "Invalid or expired claim" }, status: :forbidden
  end

  private
    def redeem_claim!
      if Sabha.saas?
        Desktop::GlobalSessionClaim.redeem!(
          token: params[:token],
          nonce: params[:nonce],
          origin: params[:origin]
        )
      else
        Desktop::SessionClaim.redeem!(
          token: params[:token],
          nonce: params[:nonce],
          origin: params[:origin]
        )
      end
    end

    def establish_session_from_claim!(claim)
      if Sabha.saas?
        global_session = claim.global_identity.global_sessions.create!(
          user_agent: request.user_agent,
          ip_address: request.remote_ip
        )
        cookies.signed.permanent[:global_session_token] = {
          value: global_session.token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
        Current.global_session = global_session
      else
        start_new_session_for(claim.user)
      end
    end
end
