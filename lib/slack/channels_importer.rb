module Slack
  class ChannelsImporter
    def initialize(context)
      @context = context
    end

    def import
      import_public_channels
      import_private_channels if @context.file_exists?("groups.json")
      import_dms if @context.file_exists?("dms.json")
    end

    private

    def import_public_channels
      channels_data = @context.parse_json("channels.json")
      @context.log "Found #{channels_data.count} public channels"

      channels_data.each do |channel|
        import_channel(channel, Rooms::Open)
      end
    end

    def import_private_channels
      groups_data = @context.parse_json("groups.json")
      @context.log "Found #{groups_data.count} private channels"

      groups_data.each do |group|
        import_channel(group, Rooms::Closed)
      end
    end

    def import_channel(channel_data, room_class)
      base_slug = channel_data["name"].to_s.parameterize

      existing_room = Room.find_by(slug: base_slug)
      if existing_room
        @context.channel_map[channel_data["id"]] = existing_room
        grant_open_room_access(existing_room) if existing_room.is_a?(Rooms::Open)
        @context.log "Room already exists: ##{existing_room.name}"
        return
      end

      room = room_class.create!(
        name: channel_data["name"].tr("-_", " ").titleize,
        slug: base_slug,
        creator: @context.admin_user
      )

      grant_membership(room, channel_data["members"])
      grant_open_room_access(room) if room.is_a?(Rooms::Open)

      @context.channel_map[channel_data["id"]] = room
      @context.increment(:rooms)
      @context.log "Created room: ##{room.name}"
    end

    def import_dms
      dms_data = @context.parse_json("dms.json")
      @context.log "Found #{dms_data.count} direct message conversations"

      dms_data.each do |dm|
        members = (dm["members"] || []).filter_map { |id| @context.user_map[id] }
        next if members.size < 2

        begin
          Current.user = members.first
          room_count_before = Rooms::Direct.count
          room = Rooms::Direct.find_or_create_for(members)
          @context.channel_map[dm["id"]] = room
          @context.increment(:rooms) if Rooms::Direct.count > room_count_before
        ensure
          Current.user = nil
        end
      end
    end

    def grant_membership(room, member_ids)
      member_users = (member_ids || []).filter_map { |id| @context.user_map[id] }
      room.memberships.grant_to(member_users) if member_users.any?
    end

    def grant_open_room_access(room)
      existing_member_ids = room.memberships.pluck(:user_id)
      users_to_add = User.active.where.not(id: existing_member_ids)
      room.memberships.grant_to(users_to_add) if users_to_add.exists?
    end
  end
end
