class SessionsController < ApplicationController
  include EmailValidation

  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Too many sign in attempts. Please try again later." }

  before_action :ensure_user_exists, only: :new
  before_action :validate_email_param, only: :create

  def new
  end

  def create
    if user = User.active.authenticate_by(email_address: params[:email_address],
                                          password: params[:password])
      # Check if email verification is required
      if Current.account.auth_method_value == "password" && !user.verified?
        redirect_to new_session_url(email_address: params[:email_address]),
          alert: "Please verify your email address. Check your inbox for the verification link, or use 'Forgot your password?' to resend."
      else
        start_new_session_for user
        redirect_to post_authenticating_url
      end
    else
      redirect_to new_session_url(email_address: params[:email_address]),
        alert: "Invalid email or password."
    end
  end

  def destroy
    remove_push_subscription
    reset_authentication
    redirect_to root_url
  end

  private
    def ensure_user_exists
      redirect_to first_run_url if User.none?
    end

    def validate_email_param
      render_invalid_email unless valid_email?(params[:email_address])
    end

    def remove_push_subscription
      if endpoint = params[:push_subscription_endpoint]
        Push::Subscription.destroy_by(endpoint: endpoint, user_id: Current.user.id)
      end
    end
end
