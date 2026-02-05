# frozen_string_literal: true

module Saas
  class RegistrationsController < BaseController
    # GlobalIdentity registration (signup) via auth code (OTP)
    #
    # Creates a new GlobalIdentity and sends an auth code for verification.
    # The user completes signup by entering the OTP code.

    allow_unauthenticated_access
    require_unauthenticated_access

    rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
      redirect_to new_registration_path, alert: "Too many attempts. Please try again later."
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
        return redirect_to new_registration_path, alert: "Please enter an email address"
      end

      # Check if GlobalIdentity already exists
      global_identity = GlobalIdentity.find_by(email_address: email)

      if global_identity
        # Existing account - send sign-in code instead
        auth_code = global_identity.auth_codes.create!(purpose: :sign_in)
        AuthCodeMailer.code(auth_code).deliver_later
      else
        # New account - create and send verification code
        global_identity = GlobalIdentity.create!(email_address: email)
        auth_code = global_identity.auth_codes.create!(purpose: :sign_up)
        AuthCodeMailer.code(auth_code).deliver_later
      end

      # Don't reveal whether email exists (prevent email enumeration)
      # Show same message regardless of whether account existed
      redirect_to auth_code_path, notice: "Check your email for a verification code"
    end
  end
end
