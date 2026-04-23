class Users::HiddenRoomsController < ApplicationController
  def index
    @hidden_memberships = SidebarMemberships.new(Current.user).hidden.load
  end
end
