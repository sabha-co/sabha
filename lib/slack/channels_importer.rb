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
      slack_channels = @context.parse_json("channels.json")
      @context.log "Found #{slack_channels.count} public channels"

      slack_channels.each do |slack_channel|
        import_channel(slack_channel, Channels::Open)
      end
    end

    def import_private_channels
      groups_data = @context.parse_json("groups.json")
      @context.log "Found #{groups_data.count} private channels"

      groups_data.each do |group|
        import_channel(group, Channels::Closed)
      end
    end

    def import_channel(slack_channel, channel_class)
      channel_name = slack_channel["name"].tr("-_", " ").titleize

      existing_channel = Channel.where("LOWER(name) = LOWER(?)", channel_name).first
      if existing_channel
        @context.channel_map[slack_channel["id"]] = existing_channel
        grant_open_channel_access(existing_channel) if existing_channel.is_a?(Channels::Open)
        @context.log "Channel already exists: ##{existing_channel.name}"
        return
      end

      channel = channel_class.create!(
        name: channel_name,
        creator: @context.admin_user
      )

      grant_membership(channel, slack_channel["members"])
      grant_open_channel_access(channel) if channel.is_a?(Channels::Open)

      @context.channel_map[slack_channel["id"]] = channel
      @context.increment(:channels)
      @context.log "Created channel: ##{channel.name}"
    end

    def import_dms
      dms_data = @context.parse_json("dms.json")
      @context.log "Found #{dms_data.count} direct message conversations"

      dms_data.each do |dm|
        members = (dm["members"] || []).filter_map { |id| @context.user_map[id] }
        next if members.size < 2

        begin
          Current.user = members.first
          channel_count_before = Channels::Direct.count
          channel = Channels::Direct.find_or_create_for(members)
          @context.channel_map[dm["id"]] = channel
          @context.increment(:channels) if Channels::Direct.count > channel_count_before
        ensure
          Current.user = nil
        end
      end
    end

    def grant_membership(channel, member_ids)
      member_users = (member_ids || []).filter_map { |id| @context.user_map[id] }
      channel.memberships.grant_to(member_users) if member_users.any?
    end

    def grant_open_channel_access(channel)
      existing_member_ids = channel.memberships.pluck(:user_id)
      users_to_add = User.active.where.not(id: existing_member_ids)
      channel.memberships.grant_to(users_to_add) if users_to_add.exists?
    end
  end
end
