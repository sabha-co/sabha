module ForcePasswordChange
  extend ActiveSupport::Concern

  included do
    before_action :require_password_change
  end

  private

  def require_password_change
    return unless Current.user&.must_change_password?

    # Allow access to password change flow and logout
    return if password_change_allowed_path?

    redirect_to change_password_path, alert: "You must change your password before continuing."
  end

  def password_change_allowed_path?
    # Allow the change password page itself
    return true if request.path == change_password_path

    # Allow logout
    return true if request.path == session_path && request.delete?

    # Allow assets and active storage
    return true if request.path.start_with?("/assets", "/rails/active_storage")

    false
  end
end
