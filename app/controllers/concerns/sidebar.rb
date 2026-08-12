module Sidebar
  extend ActiveSupport::Concern

  SIDEBAR_SECTIONS = [ :starred_rooms, :shared_rooms, :forum_rooms ].freeze

  def set_sidebar_memberships
    sidebar = SidebarMemberships.new(Current.user)

    @direct_memberships   = sidebar.direct
    @direct_room_members  = sidebar.direct_room_members(@direct_memberships)
    @starred_memberships  = sidebar.starred
    @shared_memberships   = sidebar.shared
    @forum_memberships    = sidebar.forums
  end

  def broadcast_sidebar_room_added(user, room, formats: nil)
    membership = user.memberships.find_by(room: room)
    return unless membership

    list_name = membership.sidebar_list_name
    html = render_to_string(partial: "users/sidebars/rooms/shared", formats: formats || [ :html ], locals: { list_name:, membership: membership })
    broadcast_append_to user, :rooms, target: list_name, html: html, attributes: { maintain_scroll: true }
  end

  def broadcast_sidebar_room_removed(streamable, room)
    SIDEBAR_SECTIONS.each do |list_name|
      broadcast_remove_to streamable, :rooms, target: [ room, helpers.dom_prefix(list_name, :list_node) ]
    end
  end
end
