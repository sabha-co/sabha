class Users::SidebarsController < ApplicationController
  before_action :set_sidebar_memberships, only: :show

  def show ; end

  def hidden_rooms
    @hidden_memberships = SidebarMemberships.new(Current.user).hidden.load
  end
end
