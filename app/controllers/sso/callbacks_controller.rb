class Sso::CallbacksController < Sso::BaseController
  rate_limit to: 10, within: 1.minute, only: :show, with: -> { head :too_many_requests }

  def show
    return sso_misconfigured unless sso_configured?

    payload = Sso::Payload.decode(params[:sso], params[:sig], sso_secret)
    return_path = verify_and_consume_nonce(payload.nonce)

    if payload.failed?
      raise Sso::Failed
    elsif payload.logout?
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
    def verify_and_consume_nonce(nonce)
      expected = session[SESSION_NONCE_KEY]
      raise SingleSignOnNonce::Invalid, "SSO nonce expired or invalid" unless expected.present? && expected == nonce

      return_path = SingleSignOnNonce.consume!(nonce)
      session.delete(SESSION_NONCE_KEY)
      return_path
    end

    def sign_in_via_sso(payload, return_path)
      newly_bootstrapped = FirstRun.auto_bootstrap_from_sso(payload)
      pending_join_code = session.delete(:pending_join_code)
      user = User.sign_in_with_sso!(payload)
      redeem_pending_join_code!(user, pending_join_code)
      start_new_session_for user
      flash[:notice] = welcome_message(user) if newly_bootstrapped || user.previously_new_record?
      redirect_to safe_return_path(return_path)
    end

    def welcome_message(user)
      "Welcome to #{Branding.contextual_app_name}, #{user.name}."
    end

    def sign_out_via_sso(return_path)
      terminate_session_from_cookie
      redirect_to safe_return_path(return_path)
    end

    def terminate_session_from_cookie
      session = find_session_by_cookie
      user = session&.user
      session&.destroy!
      reset_session
      cookies.delete(:session_token, domain: ENV["COOKIE_DOMAIN"])
      disconnect_remote_connections(user)
    end

    def disconnect_remote_connections(user)
      user&.disconnect_remote_connections
    rescue => error
      Rails.logger.warn("[SSO] Failed to close remote connections: #{error.class.name}: #{error.message}")
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
