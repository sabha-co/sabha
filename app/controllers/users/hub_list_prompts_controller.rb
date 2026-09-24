class Users::HubListPromptsController < ApplicationController
  # "Don't show again" on the sidebar prompt. The profile keeps its own link.
  def destroy
    Current.user.dismiss_hub_list_prompt

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hub_list_prompt") }
      format.html { redirect_back fallback_location: root_url }
    end
  end
end
