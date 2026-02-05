# frozen_string_literal: true

module Saas
  class SessionsController < BaseController
    # GlobalIdentity login via auth code (OTP)

    allow_unauthenticated_access
    require_unauthenticated_access only: [ :new, :create ]

    rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
      redirect_to new_session_path, alert: "Too many attempts. Please try again later."
    }

    def new
      # Store return_to param for redirect after authentication
      if params[:return_to].present?
        session[:return_to_after_authenticating] = params[:return_to]
      end
    end

    def create
      email = params[:email_address].to_s.strip.downcase

      if email.blank?
        return redirect_to new_session_path, alert: "Please enter an email address"
      end

      global_identity = GlobalIdentity.find_by(email_address: email)

      if global_identity
        # Existing account - send auth code
        auth_code = global_identity.auth_codes.create!(purpose: :sign_in)
        AuthCodeMailer.code(auth_code).deliver_later
      end
      # Don't reveal whether email exists (prevent email enumeration)
      # Show same message regardless of whether account exists

      redirect_to auth_code_path, notice: "If this email is registered, you'll receive a sign-in code"
    end

    def destroy
      sign_out
      redirect_to new_session_path, notice: "You have been signed out"
    end
  end
end
