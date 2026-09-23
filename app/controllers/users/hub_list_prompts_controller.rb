class Users::HubListPromptsController < ApplicationController
  # "Don't show again" on the sidebar nudge. The profile keeps its own link.
  def destroy
    Current.user.dismiss_hub_list_prompt

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hub_list_nudge") }
      format.html { redirect_back fallback_location: root_url }
    end
  end
end
