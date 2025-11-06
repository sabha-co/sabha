class UserInvolvementsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "user_#{current_user.id}_involvements"
  end
end
