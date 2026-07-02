# Curates a forum's tag set. Only a forum admin can add or remove tags
# (mirrors Accounts::BadgesController for account badges).
class Rooms::Forums::TagsController < ApplicationController
  before_action :set_forum
  before_action :ensure_can_administer
  before_action :set_tag, only: :destroy

  def create
    @tag = @forum.tags.create(tag_params)

    if @tag.persisted?
      redirect_to edit_rooms_forum_url(@forum)
    else
      redirect_to edit_rooms_forum_url(@forum), alert: @tag.errors.full_messages.join(", ")
    end
  end

  def destroy
    @tag.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@tag) }
      format.html { redirect_to edit_rooms_forum_url(@forum), status: :see_other }
    end
  end

  private
    def set_forum
      @forum = Current.user.rooms.forums.find_by(id: params[:forum_id])
      redirect_to root_url, alert: "Forum not found or inaccessible" unless @forum
    end

    def ensure_can_administer
      head :forbidden unless @forum && Current.user.can_administer?(@forum)
    end

    def set_tag
      @tag = @forum.tags.find(params[:id])
    end

    def tag_params
      params.require(:tag).permit(:name, :color)
    end
end
