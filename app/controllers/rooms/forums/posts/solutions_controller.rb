# Marks a forum post Solved (create) or reopens it (destroy). RESTful toggle
# authorized to the post's original poster or an admin (both resolved by
# User#can_administer?, which allows the record's creator). The live UI update
# rides on the model's tenant-scoped broadcasts, so the request just redirects.
class Rooms::Forums::Posts::SolutionsController < ApplicationController
  include ForumPostScoped

  before_action :set_forum
  before_action :set_post
  before_action :ensure_can_administer_post

  def create
    @post.solve!
    redirect_back fallback_location: room_url(@forum)
  end

  def destroy
    @post.reopen!
    redirect_back fallback_location: room_url(@forum)
  end
end
