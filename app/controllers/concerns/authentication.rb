module Authentication
  extend ActiveSupport::Concern
  include SessionLookup

  included do
    before_action :require_authentication
    before_action :deny_bots
    helper_method :signed_in?

    protect_from_forgery with: :exception, unless: -> { authenticated_by.bot_key? }
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    def allow_bot_access(**options)
      skip_before_action :deny_bots, **options
    end

    def require_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :restore_authentication, :deny_inactive_workspace_user, :redirect_signed_in_user_to_root, **options
    end
  end

  private
    def signed_in?
      Current.user.present?
    end

    def require_authentication
      restore_authentication || bot_authentication || request_authentication
      return if performed?

      deny_inactive_workspace_user
      require_workspace_membership unless performed?
    end

    # In SaaS mode, ensure we have a valid workspace context and membership.
    # Handles two cases:
    # 1. No tenant set (request arrived without workspace prefix) — redirect to workspace selector
    # 2. Tenant set but user isn't a member — redirect to workspace selector
    def require_workspace_membership
      return unless Sabha.saas?

      if ApplicationRecord.current_tenant.blank?
        redirect_to "/workspaces" if Current.global_session.present?
      elsif Current.user.blank?
        redirect_to "/workspaces"
      end
    end

    def restore_authentication
      session = find_session_by_cookie
      return unless session

      if session.expired?
        session.destroy
        nil
      else
        resume_session session
      end
    end

    def bot_authentication
      if (token = bearer_token) && (bot = User.authenticate_bot(token.strip))
        Current.user = bot
        set_authenticated_by(:bot_key)
      end
    end

    def bearer_token
      request.authorization&.match(/\ABearer (.+)\z/)&.[](1)
    end

    def request_authentication
      # request.url includes script_name (workspace prefix) per Rack spec
      session[:return_to_after_authenticating] = request.url unless turbo_frame_request?

      if Sabha.saas?
        # In SaaS mode, redirect to the global login page
        redirect_to "/session/new"
      else
        redirect_to new_session_url
      end
    end

    def turbo_frame_request?
      request.headers["Turbo-Frame"].present?
    end

    def redirect_signed_in_user_to_root
      redirect_to root_url if signed_in?
    end

    def redirect_signed_in_user_to_chat
      redirect_to chat_url if signed_in?
    end

    def start_new_session_for(user)
      # Preserve return_to URL before resetting session (session fixation prevention)
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to.present?

      user.sessions.start!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        authenticated_as session
      end
    end

    def resume_session(session)
      # Expired sessions are already filtered out in find_session_by_cookie
      if Sabha.saas?
        session.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
        Current.global_session = session
        ensure_workspace_user_exists if ApplicationRecord.current_tenant.present?
        set_authenticated_by(:session)
      else
        session.resume user_agent: request.user_agent, ip_address: request.remote_ip
        authenticated_as session
      end
    end

    # Banned/deactivated workspace users get bounced to /settings, which lists
    # their other workspaces. The ?denied=workspace query param tells the page
    # to render a persistent banner — flash gets clobbered by Turbo refetches
    # and auto-fades after 3s, so it's unreliable for this kind of message.
    def deny_inactive_workspace_user
      return unless Sabha.saas? && Current.user
      return unless Current.user.banned? || Current.user.deactivated?

      redirect_to settings_path(script_name: "", denied: "workspace")
    end

    # In SaaS mode, create the workspace User on first visit.
    # WorkspaceMembership#create_user! updates Current.user when the membership
    # is the active one, so the request sees the freshly-created user.
    def ensure_workspace_user_exists
      return unless Current.workspace_membership.present?
      return if Current.user.present?

      Current.workspace_membership.create_user!
    end

    def terminate_current_session
      if Sabha.saas?
        Current.global_session&.destroy
        cookies.delete(:global_session_token)
      else
        Current.session&.destroy!
        reset_session
        cookies.delete(:session_token, domain: ENV["COOKIE_DOMAIN"])
      end
    end

    def authenticated_as(session)
      return if session.user.banned?
      return if session.user.deactivated?

      Current.session = session
      set_authenticated_by(:session)
      set_authentication_cookie(session)
      request.session[:user_id] = session.user.id
    end

    def store_return_to
      if params[:return_to].present? && safe_redirect_url?(params[:return_to])
        session[:return_to_after_authenticating] = params[:return_to]
      end
    end

    def post_authenticating_url
      return_url = session.delete(:return_to_after_authenticating)
      safe_redirect_url?(return_url) ? return_url : root_url
    end

    def safe_redirect_url?(url)
      uri = URI.parse(url)
      uri.host.blank? || uri.host == URI.parse(root_url).hostname
    rescue URI::InvalidURIError
      false
    end

    def set_authentication_cookie(session)
      cookies.signed.permanent[:session_token] = {
        value: session.token,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?,
        domain: ENV["COOKIE_DOMAIN"]
      }
    end

    def remove_authentication_cookie
      cookies.delete(:session_token, domain: ENV["COOKIE_DOMAIN"])
    end

    def deny_bots
      head :forbidden if authenticated_by.bot_key?
    end

    def set_authenticated_by(method)
      @authenticated_by = method.to_s.inquiry
    end

    def authenticated_by
      @authenticated_by ||= "".inquiry
    end
end
