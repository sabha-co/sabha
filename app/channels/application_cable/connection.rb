module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Authentication::SessionLookup

    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private
      def find_verified_user
        if verified_session = find_session_by_cookie
          verified_session.user
        else
          reject_unauthorized_connection
        end
      end
  end
end
