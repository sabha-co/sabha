class UsersController < ApplicationController
  include NotifyBots
  include EmailValidation

  require_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_to new_session_url, alert: "Too many signup attempts. Please try again later." }

  before_action :set_user, only: :show
  before_action :set_join_code, only: %i[ new create ]
  before_action :verify_join_code_active, only: %i[ new create ]
  before_action :set_return_to_url, only: %i[ new create ]
  before_action :validate_email_param, only: :create, unless: -> { saas_authenticated? || saas_unauthenticated? }
  before_action :start_otp_if_user_exists, only: :create, if: -> { !saas_authenticated? && !saas_unauthenticated? && Current.account.auth_method_value == "otp" }

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
    @recent_messages = Current.user.reachable_messages.created_by(@user).with_creator.ordered.last(5).reverse
  end

  private
    # SaaS mode: user is globally authenticated, just needs to join this workspace
    def create_for_saas_user
      global_identity = Current.global_identity

      # Create records first, then redeem join code
      # This avoids burning limited-use invites on creation failures
      membership = WorkspaceMembership.create!(
        global_identity: global_identity,
        tenant: ApplicationRecord.current_tenant
      )

      @user = membership.create_user!

      # Redeem join code after successful creation
      unless redeem_join_code
        cleanup_failed_join(membership, @user)
        redirect_to root_url, alert: "This invite link is no longer valid.", status: :see_other
        return
      end

      deliver_webhooks_to_bots(@user, :created)

      # Set up Current context so redirect works correctly
      Current.workspace_membership = membership

      redirect_to root_url, notice: "Welcome to #{Current.account.name}!"
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(WorkspaceMembership) && e.record.errors[:global_identity_id].present?
        redirect_to root_url, notice: "You're already a member of this workspace."
      else
        flash.now[:alert] = e.record.errors.full_messages.to_sentence
        @user = User.new
        set_member_counts
        render :new, status: :unprocessable_entity
      end
    end

    # Clean up records if join code redemption fails
    # Note: Cross-database operations can't be transactional
    def cleanup_failed_join(membership, user)
      user&.destroy! if user&.persisted?
      membership&.destroy! if membership&.persisted?
    rescue ActiveRecord::RecordNotDestroyed => e
      # Log but don't raise - orphaned records are preferable to burned invites
      Rails.logger.error("[JoinCleanup] Failed to cleanup after join failure: #{e.message}")
    end

    # Self-hosted mode or unauthenticated SaaS: full signup flow
    def create_for_new_user
      # Validate password for password-based authentication
      if Current.account.auth_method_value == "password"
        return unless validate_password_params
      end

      # Create user first, then redeem join code
      # This avoids burning limited-use invites on creation failures
      @user = User.create!(user_params)

      unless redeem_join_code
        @user.destroy!
        redirect_to root_url, alert: "This invite link is no longer valid. Please request a new one.", status: :see_other
        return
      end

      deliver_webhooks_to_bots(@user, :created)

      # Always require email verification for new users
      if @user.person? && !@user.verified?
        if Current.account.auth_method_value == "otp"
          # For OTP: Send verification code
          start_otp_for @user
          redirect_to new_auth_tokens_validations_path, notice: "Please check your email for a verification code.", status: :see_other
        else
          # For password: Send verification email with link
          @user.send_verification_email
          redirect_to new_session_url(email_address: @user.email_address), notice: "Please check your email to verify your account.", status: :see_other
        end
      else
        start_new_session_for @user
        redirect_to root_url
      end
    rescue ActiveRecord::RecordNotUnique
      redirect_to new_session_url(email_address: user_params[:email_address]), notice: "An account with this email already exists. Please sign in.", status: :see_other
    end

    def set_user
      @user = User.find(params[:id])
    end

    def set_join_code
      @join_code = Current.account.join_codes.find_by(code: params[:join_code])
      head :not_found unless @join_code
    end

    def verify_join_code_active
      head :gone unless @join_code.active?
    end

    def redeem_join_code
      @join_code.redeem
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

    def validate_password_params
      @user = User.new

      if user_params[:password].blank?
        flash.now[:alert] = "Password can't be blank"
        set_member_counts
        render :new, status: :unprocessable_entity
        return false
      elsif user_params[:password].length < User::MINIMUM_PASSWORD_LENGTH
        flash.now[:alert] = "Password is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
        set_member_counts
        render :new, status: :unprocessable_entity
        return false
      end

      true
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
      @online_user_count = Rails.cache.fetch(tenant_cache_key("users/online_count"), expires_in: 5.minutes) do
        User.active.verified.where(last_authenticated_at: 24.hours.ago..).count
      end
      @member_count = Rails.cache.fetch(tenant_cache_key("users/member_count"), expires_in: 5.minutes) do
        User.active.verified.count
      end
    end

    def tenant_cache_key(key)
      if Campfire.saas? && ApplicationRecord.current_tenant.present?
        "#{ApplicationRecord.current_tenant}/#{key}"
      else
        key
      end
    end

    # Check if user is globally authenticated in SaaS mode (but not yet a workspace member)
    def saas_authenticated?
      Campfire.saas? && Current.global_identity.present? && Current.user.blank?
    end

    # Check if user is unauthenticated in SaaS mode
    def saas_unauthenticated?
      Campfire.saas? && Current.global_identity.blank?
    end

    # Build return_to URL for auth redirects
    # request.fullpath already includes script_name (workspace prefix) per Rack spec
    def set_return_to_url
      @return_to_url = request.fullpath
    end
end
