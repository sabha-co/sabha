class Sso::CallbacksController < Sso::BaseController
  rate_limit to: 10, within: 1.minute, only: :show, with: -> { head :too_many_requests }

  def show
    return sso_misconfigured unless sso_configured?

    payload = Sso::Payload.decode(params[:sso], params[:sig], sso_secret)
    return_path = SingleSignOnNonce.consume!(payload["nonce"], session:)

    if payload["failed"]
      raise Sso::Failed
    elsif payload["logout"]
      sign_out_via_sso(return_path)
    else
      sign_in_via_sso(payload, return_path)
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
    def sign_in_via_sso(payload, return_path)
      pending_join_code = session.delete(:pending_join_code)
      user = User.sign_in_with_sso!(payload)
      redeem_pending_join_code!(user, pending_join_code)
      start_new_session_for user
      redirect_to safe_return_path(return_path)
    end

    def sign_out_via_sso(return_path)
      terminate_session_from_cookie
      redirect_to safe_return_path(return_path)
    end

    def terminate_session_from_cookie
      find_session_by_cookie&.destroy!
      reset_session
      cookies.delete(:session_token, domain: ENV["COOKIE_DOMAIN"])
    end

    def redeem_pending_join_code!(user, code)
      return if code.blank?

      join_code = Current.account.join_codes.human.find_by(code: code)

      if user.previously_new_record?
        unless join_code&.redeem
          user.destroy!
          raise Sso::Forbidden.new(
            "Join code inactive at SSO callback",
            user_message: "This invite link is no longer valid. Please request a new one."
          )
        end
      else
        join_code&.redeem
      end
    end
end
