class Users::PresencesController < ApplicationController
  # An unknown state is a bad request, not a new state. Rails raises on an
  # out-of-range enum rather than failing validation, so that's what's caught.
  rescue_from ArgumentError, ActionController::ParameterMissing do
    head :unprocessable_entity
  end

  # Always the signed-in user. The route carries no id to spoof, and nothing here
  # reads one — you can only ever say where *you* are.
  def update
    Current.user.change_presence! params.require(:user).require(:presence)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back fallback_location: root_url }
    end
  end
end
