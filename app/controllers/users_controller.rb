class UsersController < ApplicationController
  include NotifyBots
  include EmailValidation
  include BlockBannedRequests

  require_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_to new_session_url, alert: "Too many signup attempts. Please try again later." }

  before_action :set_user, only: :show
  before_action :reject_banned_ip, only: :create
  before_action :set_join_code, only: %i[ new create ]
  before_action :verify_join_code_active, only: %i[ new create ]
  before_action :redirect_to_sso_login, only: %i[ new create ], if: -> { Account.sso_auth? && !signed_in? }
  before_action :validate_cloudflare_turnstile, only: :create, unless: -> { Sabha.saas? }
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :handle_turnstile_failure

  before_action :set_return_to_url, only: %i[ new create ]
  before_action :validate_email_param, only: :create, unless: -> { saas_authenticated? || saas_unauthenticated? }
  before_action :ensure_password_provided, only: :create, unless: -> { saas_authenticated? || saas_unauthenticated? }
  before_action :start_otp_if_user_exists, only: :create, if: -> { !saas_authenticated? && !saas_unauthenticated? && Account.otp_auth? }

  helper_method :saas_authenticated?, :saas_unauthenticated?

  def new
    @user = User.new
    set_member_counts
  end

  def create
    if saas_unauthenticated?
      # Unauthenticated SaaS users can't submit - redirect to login
      redirect_to "/session/new", alert: "Please sign in to join this workspace."
    elsif saas_authenticated?
      create_for_saas_user
    else
      create_for_new_user
    end
  end

  def show
    @recent_messages = Current.user.reachable_messages.user_authored.created_by(@user).with_creator.ordered.last(5).reverse
    @shared_room_count = Current.user.shared_room_count_with(@user)
  end

  private
    def handle_turnstile_failure
      redirect_back fallback_location: root_url, alert: "Please complete the CAPTCHA verification."
    end

    def redirect_to_sso_login
      session[:pending_join_code] = @join_code.code
      redirect_to sso_handshake_url(return_to: request.fullpath)
    end

    # SaaS mode: user is globally authenticated, just needs to join this workspace.
    # Idempotent on (identity, tenant) so retries collapse into the same membership;
    # the code is burned only when the join actually creates a new membership.
    def create_for_saas_user
      membership = nil
      redeemed = @join_code.redeem_if do
        membership = Current.global_identity.join(ApplicationRecord.current_tenant)
        membership.previously_new_record?
      end

      # Lost a race: code went inactive between before_action and the lock.
      return redirect_to(root_url, alert: "This invite link is no longer valid.", status: :see_other) unless membership

      Current.workspace_membership = membership
      @user = membership.user

      notify_bots(@user, :created) if redeemed
      redirect_to root_url, notice: "Welcome to #{Current.account.name}!"
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.record.errors.full_messages.to_sentence
      @user = User.new
      set_member_counts
      render :new, status: :unprocessable_entity
    end

    # Self-hosted mode or unauthenticated SaaS: full signup flow
    def create_for_new_user
      @user = User.create!(user_params)
      @join_code.redeem!
      notify_bots(@user, :created)
      redirect_after_signup
    rescue Account::JoinCode::InactiveCodeError
      @user.destroy!
      redirect_to root_url, alert: "This invite link is no longer valid. Please request a new one.", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.record.errors.full_messages.to_sentence
      @user = User.new
      set_member_counts
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      redirect_to new_session_url(email_address: user_params[:email_address]),
        notice: "An account with this email already exists. Please sign in.", status: :see_other
    end

    def set_user
      @user = User.find(params[:id])
    end

    def set_join_code
      @join_code = Current.account.join_codes.human.find_by(code: params[:join_code])
      redirect_to root_url, alert: "This invite link is not valid. Please request a new one." unless @join_code
    end

    def verify_join_code_active
      redirect_to root_url, alert: "This invite link has expired. Please request a new one." unless @join_code.active?
    end

    def start_otp_if_user_exists
      user = User.active.find_by(email_address: user_params[:email_address])

      if user&.ever_authenticated?
        start_otp_for user
        redirect_to new_auth_tokens_validations_path
      end
    end

    def start_otp_for(user)
      session[:otp_email_address] = user.email_address

      auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
      auth_token.deliver_later
    end

    def ensure_password_provided
      return unless Account.password_auth?
      return if user_params[:password].present?

      @user = User.new
      flash.now[:alert] = "Password can't be blank"
      set_member_counts
      render :new, status: :unprocessable_entity
    end

    def redirect_after_signup
      if @user.person? && !@user.verified?
        if Account.otp_auth?
          start_otp_for @user
          redirect_to new_auth_tokens_validations_path, notice: "Please check your email for a verification code.", status: :see_other
        else
          @user.send_verification_email
          redirect_to new_session_url(email_address: @user.email_address), notice: "Please check your email to verify your account.", status: :see_other
        end
      else
        start_new_session_for @user
        redirect_to root_url
      end
    end

    def user_params
      permitted_params = params.require(:user).permit(:name, :avatar, :email_address, :password)
      permitted_params[:email_address]&.downcase!
      permitted_params
    end

    def validate_email_param
      render_invalid_email unless valid_email?(params.dig(:user, :email_address))
    end

    def set_member_counts
      @here_now_count_extended = Rails.cache.fetch(ApplicationRecord.tenant_cache_key("users/here_now_count_extended"), expires_in: 5.minutes) do
        Membership.connected_member_count(since: Membership::Connectable::ACTIVITY_TIERS[:recently_active])
      end
      @member_count = User.member_count
    end

    # Check if user is globally authenticated in SaaS mode (but not yet a workspace member)
    def saas_authenticated?
      Sabha.saas? && Current.global_identity.present? && Current.user.blank?
    end

    # Check if user is unauthenticated in SaaS mode
    def saas_unauthenticated?
      Sabha.saas? && Current.global_identity.blank?
    end

    # Build return_to URL for auth redirects
    # request.fullpath already includes script_name (workspace prefix) per Rack spec
    def set_return_to_url
      @return_to_url = request.fullpath
    end
end
