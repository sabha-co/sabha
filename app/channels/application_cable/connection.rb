module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Authentication::SessionLookup

    identified_by :current_user
    # Note: In SaaS mode, the gem provides `current_tenant` via CableConnection::Base
    # which is set automatically and used by `around_command :with_tenant`

    def connect
      # Call super first to let the gem set current_tenant from tenant_resolver
      super if Sabha.saas?

      if request.params["bot_key"].present?
        connect_bot
      elsif Sabha.saas?
        connect_saas
      else
        connect_single_tenant
      end
    end

    private
      def connect_bot
        bot = if Sabha.saas?
          return reject_unauthorized_connection unless current_tenant
          ApplicationRecord.with_tenant(current_tenant) { User.authenticate_bot(request.params["bot_key"]) }
        else
          User.authenticate_bot(request.params["bot_key"])
        end

        reject_unauthorized_connection unless bot
        self.current_user = bot
      end

      def connect_single_tenant
        verified_session = find_session_by_cookie
        return reject_unauthorized_connection unless verified_session

        # Reject expired sessions
        return reject_unauthorized_connection if verified_session.expired?

        user = verified_session.user
        return reject_unauthorized_connection unless user

        # Reject banned or deactivated users
        return reject_unauthorized_connection if user.banned? || user.deactivated?

        self.current_user = user
      end

      def connect_saas
        global_session = find_session_by_cookie
        return reject_unauthorized_connection unless global_session

        # Reject expired sessions
        return reject_unauthorized_connection if global_session.expired?

        # current_tenant is already set by the gem via tenant_resolver
        ws_id = current_tenant
        return reject_unauthorized_connection unless ws_id

        # Find the membership for this identity + workspace
        membership = global_session.global_identity.workspace_memberships.find_by(tenant: ws_id)
        return reject_unauthorized_connection unless membership

        # Get the User from the workspace (or create lazily)
        user = ApplicationRecord.with_tenant(ws_id) do
          membership.user || membership.create_user!
        end
        return reject_unauthorized_connection unless user

        # Reject banned or deactivated users (matches single-tenant behavior)
        return reject_unauthorized_connection if user.banned? || user.deactivated?

        self.current_user = user
      end
  end
end
