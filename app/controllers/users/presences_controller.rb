class Users::PresencesController < ApplicationController
  # Missing and unrecognised both mean the same thing here, and both are caught
  # at the boundary rather than by rescuing whatever the update happens to raise
  # — an ArgumentError from further in is a bug, not a bad request.
  rescue_from ActionController::ParameterMissing do
    head :unprocessable_entity
  end

  # Always the signed-in user. The route carries no id to spoof, and nothing here
  # reads one — you can only ever say where *you* are.
  def update
    Current.user.change_availability! chosen_availability

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back fallback_location: root_url }
    end
  end

  private
    def chosen_availability
      params.require(:user).require(:availability).presence_in(User.availabilities.keys) ||
        raise(ActionController::ParameterMissing, :availability)
    end
end
