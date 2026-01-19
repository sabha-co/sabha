module Sidebar
  extend ActiveSupport::Concern

  included do
    helper_method :for_each_sidebar_section
  end

  def set_sidebar_memberships
    sidebar = SidebarMemberships.new(Current.user)

    @direct_memberships  = sidebar.direct
    @direct_room_members = sidebar.direct_room_members(@direct_memberships)
    @shared_memberships  = sidebar.shared
  end

  def for_each_sidebar_section
    [ :starred_rooms, :shared_rooms ].each { |name| yield name }
  end
end
