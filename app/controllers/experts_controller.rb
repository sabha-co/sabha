class ExpertsController < ApplicationController
  def show
    @expert_users = User.where(id: Expert.user_ids).index_by(&:id)
    render layout: "application"
  end
end
