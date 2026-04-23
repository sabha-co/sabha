class Users::AvatarShufflesController < ApplicationController
  def create
    Current.user.shuffle_avatar_seed!
    redirect_to user_profile_url
  end
end
