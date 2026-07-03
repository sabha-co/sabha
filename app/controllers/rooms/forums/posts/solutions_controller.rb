# Marks a forum post Solved (create) or reopens it (destroy). RESTful toggle
# authorized to the post's original poster or an admin (both resolved by
# User#can_administer?, which allows the record's creator). The live UI update
# rides on the model's tenant-scoped broadcasts, so the request just redirects.
class Rooms::Forums::Posts::SolutionsController < ApplicationController
  before_action :set_post
  before_action :ensure_can_resolve

  def create
    @post.solve!
    redirect_back fallback_location: room_url(@forum)
  end

  def destroy
    @post.reopen!
    redirect_back fallback_location: room_url(@forum)
  end

  private
    def set_post
      @forum = Current.user.rooms.forums.find_by(id: params[:forum_id])
      @post = @forum&.threads&.find_by(id: params[:post_id])
      redirect_to root_url, alert: "Post not found or inaccessible" unless @post
    end

    def ensure_can_resolve
      head :forbidden unless @post && Current.user.can_administer?(@post)
    end
end
