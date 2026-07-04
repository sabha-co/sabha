# Follow (create) / Unfollow (destroy) a forum post — the state-as-records form
# of "notify me of replies without having replied." Access derives from forum
# membership; this manages only the current user's own follow on the post.
class Rooms::Posts::MembershipsController < ApplicationController
  before_action :set_post

  def create
    @post.follow!(Current.user)
    redirect_back fallback_location: forum_post_url(@post.slug)
  end

  def destroy
    @post.unfollow!(Current.user)
    redirect_back fallback_location: forum_post_url(@post.slug)
  end

  private
    def set_post
      @post = Rooms::Post.active.find_by(id: params[:post_id])
      head :forbidden unless @post&.viewable_by?(Current.user)
    end
end
