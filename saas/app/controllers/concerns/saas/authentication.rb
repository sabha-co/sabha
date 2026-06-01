# frozen_string_literal: true

module Saas
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :set_current_global_session
      helper_method :signed_in?, :current_global_identity
    end

    class_methods do
      def require_authentication(**options)
        before_action :require_global_identity, **options
      end

      def allow_unauthenticated_access(**options)
        skip_before_action :require_global_identity, raise: false, **options
      end

      def require_unauthenticated_access(**options)
        before_action :redirect_authenticated_user, **options
      end
    end

    private

      # Set current global session from cookie
      def set_current_global_session
        token = cookies.signed[:global_session_token]
        return unless token

        session = GlobalSession.find_by(token: token)
        if session&.expired?
          session.destroy
          cookies.delete(:global_session_token)
        else
          Current.global_session = session
        end
      end

      # Check if user is signed in (has valid GlobalIdentity)
      def signed_in?
        Current.global_identity.present?
      end

      # Current GlobalIdentity (cross-workspace identity)
      def current_global_identity
        Current.global_identity
      end

      # Require GlobalIdentity to be present
      def require_global_identity
        return if signed_in?

        store_location_for_redirect
        redirect_to new_session_path, alert: "Please sign in to continue"
      end

      # Redirect if already authenticated (for login/signup pages)
      def redirect_authenticated_user
        return unless signed_in?

        redirect_to after_authentication_url
      end

      # Sign in a GlobalIdentity by creating a GlobalSession
      def sign_in(global_identity)
        # Preserve return_to URL before resetting session (session fixation prevention)
        return_to = session[:return_to_after_authenticating]
        reset_session
        session[:return_to_after_authenticating] = return_to if return_to.present?

        global_session = global_identity.global_sessions.create!(
          user_agent: request.user_agent,
          ip_address: request.remote_ip
        )

        cookies.signed.permanent[:global_session_token] = {
          value: global_session.token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }

        Current.global_session = global_session
      end

      # Sign out by destroying the GlobalSession
      def sign_out
        Current.global_session&.destroy
        cookies.delete(:global_session_token)
        Current.global_session = nil
      end

      # Store the current URL for redirect after authentication
      # request.fullpath includes script_name (workspace prefix) per Rack spec
      # Check both GET and HEAD since HEAD is routed like GET but request.get? returns false
      def store_location_for_redirect
        session[:return_to_after_authenticating] = request.fullpath if request.get? || request.head?
      end

      # Capture the post-authentication redirect target from params, clearing any
      # previously stored value when none is supplied. Clearing matters because an
      # abandoned flow (e.g. SSO arriving with a return_to) would otherwise leave a
      # stale, cross-origin target that hijacks the next unrelated plain login.
      def capture_return_to
        session[:return_to_after_authenticating] = params[:return_to].presence
      end

      # URL to redirect to after successful authentication
      def after_authentication_url
        stored_url = session.delete(:return_to_after_authenticating)
        return stored_url if stored_url.present? && safe_redirect_url?(stored_url)

        # Default: go to root (shows blank page with workspace selector)
        saas_root_path
      end

      # Check if URL is safe to redirect to (same origin, valid workspace)
      def safe_redirect_url?(url)
        return false if url.blank?

        uri = URI.parse(url)
        # Only allow relative URLs or same-host URLs
        return false unless uri.host.nil? || uri.host == request.host

        # If URL starts with a workspace external_id, verify access
        path = uri.path || url
        if (match = path.match(%r{\A/(\d+)(/.*)?$}))
          workspace_id = match[1]
          subpath = match[2] || ""

          # Join URLs are allowed if the workspace exists (user isn't a member yet)
          if subpath.start_with?("/join/")
            return Workspace.exists?(external_id: workspace_id)
          end

          # Other workspace URLs require membership
          return workspace_accessible?(workspace_id)
        end

        true
      rescue URI::InvalidURIError
        false
      end

      # Check if the user has access to a workspace by external_id
      def workspace_accessible?(external_id)
        return false unless current_global_identity

        current_global_identity
          .workspace_memberships
          .exists?(tenant: external_id.to_s)
      end
  end
end
