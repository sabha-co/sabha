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

    before_action :validate_cloudflare_turnstile, only: :create
    rescue_from RailsCloudflareTurnstile::Forbidden, with: :handle_turnstile_failure

    def new
      capture_return_to
    end

    def create
      # Check if GlobalIdentity already exists (normalizes handles case/whitespace)
      global_identity = GlobalIdentity.find_by(email_address: params[:email_address])

      if global_identity
        # Name intentionally ignored for existing accounts (anti-enumeration)
        auth_code = global_identity.auth_codes.create!(purpose: :sign_in)
        auth_code.deliver_later
      else
        # New account - create and send verification code
        global_identity = GlobalIdentity.create!(name: params[:name], email_address: params[:email_address], terms_of_service: params[:terms_of_service])
        auth_code = global_identity.auth_codes.create!(purpose: :sign_up)
        auth_code.deliver_later
      end

      # Don't reveal whether email exists (prevent email enumeration)
      # Show same message regardless of whether account existed
      session[:auth_code_email] = params[:email_address].to_s.strip
      redirect_to auth_code_path, notice: "Check your email for a verification code"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to new_registration_path, alert: e.record.errors.full_messages.to_sentence
    end

    private

      def handle_turnstile_failure
        redirect_to new_registration_path, alert: "Please complete the CAPTCHA verification."
      end
  end
end
