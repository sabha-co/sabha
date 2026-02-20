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

  def broadcast_sidebar_room_added(user, room, formats: nil)
    for_each_sidebar_section do |list_name|
      html = render_to_string(partial: "users/sidebars/rooms/shared", formats: formats || [ :html ], locals: { list_name:, room: room })
      broadcast_append_to user, :rooms, target: list_name, html: html, attributes: { maintain_scroll: true }
    end
  end

  def broadcast_sidebar_room_removed(user, room)
    for_each_sidebar_section do |list_name|
      broadcast_remove_to user, :rooms, target: [ room, helpers.dom_prefix(list_name, :list_node) ]
    end
  end
end
