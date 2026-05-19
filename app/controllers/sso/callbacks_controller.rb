class Sso::CallbacksController < Sso::BaseController
  rate_limit to: 10, within: 1.minute, only: :show, with: -> { head :too_many_requests }

  def show
    return sso_misconfigured unless sso_configured?

    payload = Sso::Payload.decode(params[:sso], params[:sig], sso_secret)
    return_path = SingleSignOnNonce.consume!(payload["nonce"], session:)

    if payload["failed"]
      raise Sso::Failed
    elsif payload["logout"]
      terminate_session_from_cookie
      redirect_to safe_return_path(return_path)
    else
      start_new_session_for User.sign_in_with_sso!(payload)
      redirect_to safe_return_path(return_path)
    end
  rescue Sso::Payload::Error, SingleSignOnNonce::Error => error
    Rails.logger.warn("[SSO] Rejected callback: #{error.class.name}: #{error.message}")
    head :forbidden
  rescue Sso::Error => error
    Rails.logger.warn("[SSO] Sign-in failed: #{error.class.name}: #{error.message}")
    @message = error.user_message
    render "sso/failed", status: error.status
  end

  private
    def terminate_session_from_cookie
      find_session_by_cookie&.destroy!
      reset_session
      cookies.delete(:session_token, domain: ENV["COOKIE_DOMAIN"])
    end
end
