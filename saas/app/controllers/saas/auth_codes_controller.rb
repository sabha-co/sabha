# frozen_string_literal: true

module Saas
  class AuthCodesController < BaseController
    # OTP code verification for GlobalIdentity authentication
    #
    # Parallels AuthTokens::ValidationsController in self-hosted mode

    allow_unauthenticated_access

    rate_limit to: 10, within: 15.minutes, only: :create, with: -> {
      redirect_to auth_code_path, alert: "Too many attempts. Please request a new code."
    }

    def show
      @auth_code_email = session.delete(:auth_code_email)

      # Store return_to param for redirect after authentication
      if params[:return_to].present?
        session[:return_to_after_authenticating] = params[:return_to]
      end
    end

    def create
      code = params[:code].to_s
      auth_code = AuthCode.find_active(code)

      if auth_code
        global_identity = auth_code.consume

        if auth_code.email_change?
          handle_email_change(global_identity)
        else
          handle_authentication(global_identity, is_new_user: auth_code.sign_up?)
        end
      else
        redirect_to auth_code_path, alert: "Invalid or expired code. Please try again."
      end
    end

    private

      def handle_authentication(global_identity, is_new_user:)
        global_identity.verify! unless global_identity.verified?
        sign_in(global_identity)

        notice = is_new_user ? "Welcome!" : "Welcome back!"
        redirect_to after_authentication_url, notice: notice
      end

      def handle_email_change(global_identity)
        result = global_identity.confirm_email_change!

        if result
          old_email, new_email = result
          sign_in(global_identity)
          redirect_to workspaces_path, notice: "Email changed from #{old_email} to #{new_email}"
        else
          redirect_to workspaces_path, alert: "No pending email change found"
        end
      end
  end
end
