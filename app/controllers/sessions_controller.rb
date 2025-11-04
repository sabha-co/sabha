class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render_rejection :too_many_requests }

  before_action :ensure_user_exists, only: :new

  def new
  end

  def create
    if user = User.active.non_suspended.authenticate_by(email_address: params[:email_address],
                                                         password: params[:password])
      # Check if email verification is required
      if ENV["AUTH_METHOD"] == "password" && !user.verified?
        flash.now[:alert] = "Please verify your email address. Check your inbox for the verification link, or use 'Forgot your password?' to resend."
        render :new, status: :unauthorized
      else
        start_new_session_for user
        redirect_to post_authenticating_url
      end
    else
      render_rejection :unauthorized
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

    def render_rejection(status)
      flash.now[:alert] = "Too many requests or unauthorized."
      render :new, status: status
    end

    def remove_push_subscription
      if endpoint = params[:push_subscription_endpoint]
        Push::Subscription.destroy_by(endpoint: endpoint, user_id: Current.user.id)
      end
    end
end
