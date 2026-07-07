# Follow (create) / Unfollow (destroy) a chat thread — the state-as-records form
# of "notify me of replies without having replied." Access derives from the parent
# room; this manages only the current user's own follow on the thread. Mirrors
# Rooms::Posts::MembershipsController.
class Rooms::Threads::MembershipsController < ApplicationController
  before_action :set_thread

  def create
    @thread.follow!(Current.user)
    respond_with_follow_change
  end

  def destroy
    @thread.unfollow!(Current.user)
    respond_with_follow_change
  end

  private
    # Flip the Follow/Unfollow button in its frame for the actor without a reload.
    # A thread has no gallery card (unlike a post), so only the follow control
    # refreshes. JS off falls back to reopening the thread panel.
    def respond_with_follow_change
      if turbo_frame_request?
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@thread, :follow),
          partial: "rooms/threads/follow_control", locals: { thread: @thread })
      else
        redirect_to rooms_thread_path(@thread)
      end
    end

    def set_thread
      @thread = Rooms::Thread.active.find_by(id: params[:thread_id])
      return head :not_found unless @thread
      head :forbidden unless @thread.viewable_by?(Current.user)
    end
end
