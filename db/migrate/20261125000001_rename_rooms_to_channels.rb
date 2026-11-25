class RenameRoomsToChannels < ActiveRecord::Migration[8.2]
  STI_TYPES = %w[ Open Closed Forum Direct Thread Post ]
  POLYMORPHIC_COLUMNS = { action_text_rich_texts: :record_type, active_storage_attachments: :record_type, storage_entries: :recordable_type, storage_totals: :owner_type }
  EVENTS = { "room_created" => "channel_created", "room_renamed" => "channel_renamed" }
  SYSTEM_BODIES = { "channel_created" => [ "created the room", "created the channel" ], "channel_renamed" => [ "renamed the room from", "renamed the channel from" ] }
  SETTINGS = { "restrict_room_creation_to_administrators" => "restrict_channel_creation_to_administrators" }
  INDEXES = {
    channels: { "index_rooms_on_parent_room_and_created" => "index_channels_on_parent_channel_and_created",
                "index_rooms_on_parent_room_and_activity" => "index_channels_on_parent_channel_and_activity" },
    messages: { "index_messages_on_active_room_created" => "index_messages_on_active_channel_created" }
  }

  def up
    remove_index :rooms, name: "index_rooms_on_parent_message_id_unique_thread"

    rename_table :rooms, :channels
    rename_column :channels, :parent_room_id, :parent_channel_id
    rename_column :memberships, :room_id, :channel_id
    rename_column :messages, :room_id, :channel_id
    INDEXES.each { |table, names| names.each { |from, to| rename_index table, from, to } }

    rename_types "Room", "Rooms", "Channel", "Channels"
    add_index :channels, :parent_message_id, unique: true, where: "type = 'Channels::Thread' AND parent_message_id IS NOT NULL", name: "index_channels_on_parent_message_id_unique_thread"

    EVENTS.each { |from, to| rename_event from, to }
    SYSTEM_BODIES.each { |event, (from, to)| rewrite_system_bodies event, from, to }
    SETTINGS.each { |from, to| rename_setting from, to }
    rewrite_links "rooms", "channels"
  end

  def down
    remove_index :channels, name: "index_channels_on_parent_message_id_unique_thread"

    rewrite_links "channels", "rooms"
    SETTINGS.each { |from, to| rename_setting to, from }
    SYSTEM_BODIES.each { |event, (from, to)| rewrite_system_bodies event, to, from }
    EVENTS.each { |from, to| rename_event to, from }
    rename_types "Channel", "Channels", "Room", "Rooms"

    INDEXES.each { |table, names| names.each { |from, to| rename_index table, to, from } }
    rename_column :messages, :channel_id, :room_id
    rename_column :memberships, :channel_id, :room_id
    rename_column :channels, :parent_channel_id, :parent_room_id
    rename_table :channels, :rooms

    add_index :rooms, :parent_message_id, unique: true, where: "type = 'Rooms::Thread' AND parent_message_id IS NOT NULL", name: "index_rooms_on_parent_message_id_unique_thread"
  end

  private
    def rename_types(base_from, namespace_from, base_to, namespace_to)
      table = table_exists?(:channels) ? :channels : :rooms
      STI_TYPES.each { |type| update_column_value table, :type, "#{namespace_from}::#{type}", "#{namespace_to}::#{type}" }

      POLYMORPHIC_COLUMNS.each do |polymorphic_table, column|
        next unless table_exists?(polymorphic_table)

        update_column_value polymorphic_table, column, base_from, base_to
        STI_TYPES.each { |type| update_column_value polymorphic_table, column, "#{namespace_from}::#{type}", "#{namespace_to}::#{type}" }
      end
    end

    def rename_event(from, to)
      update_column_value :messages, :event, from, to
    end

    def update_column_value(table, column, from, to)
      execute "UPDATE #{quote_table_name(table)} SET #{quote_column_name(column)} = #{quote(to)} WHERE #{quote_column_name(column)} = #{quote(from)}"
    end

    def rewrite_system_bodies(event, from, to)
      execute <<~SQL
        UPDATE action_text_rich_texts SET body = REPLACE(body, #{quote(from)}, #{quote(to)})
        WHERE record_type = 'Message' AND name = 'body'
          AND record_id IN (SELECT id FROM messages WHERE event = #{quote(event)})
      SQL
    end

    def rename_setting(from, to)
      select_rows("SELECT id, settings FROM accounts WHERE settings IS NOT NULL").each do |id, json|
        settings = json.is_a?(String) ? JSON.parse(json) : json
        next unless settings.is_a?(Hash) && settings.key?(from)

        settings[to] = settings.delete(from)
        execute "UPDATE accounts SET settings = #{quote(settings.to_json)} WHERE id = #{Integer(id)}"
      end
    end

    # Links to this install's own pages: relative hrefs, or absolute URLs on its
    # own host, with or without a workspace prefix. Other sites' /rooms/ paths
    # stay as they are.
    def rewrite_links(from, to)
      hosts = [ ENV["APP_HOST"].presence, own_host_from_mailer ].compact.uniq.map { |host| Regexp.escape(host) }
      prefix = hosts.any? ? %r{href=["']|https?://(?:#{hosts.join("|")})} : %r{href=["']}
      pattern = %r{(#{prefix})(/\d+)?/#{from}(?=[/?#"'<\s]|\z)}

      rich_texts = Arel::Table.new(name: "action_text_rich_texts")
      query = rich_texts.project(rich_texts[:id], rich_texts[:body]).where(rich_texts[:body].matches("%/#{from}%"))

      select_rows(query.to_sql).each do |id, body|
        rewritten = body.gsub(pattern) { "#{$1}#{$2}/#{to}" }
        execute "UPDATE action_text_rich_texts SET body = #{quote(rewritten)} WHERE id = #{Integer(id)}" unless rewritten == body
      end
    end

    def own_host_from_mailer
      options = ActionMailer::Base.default_url_options
      options[:host] && [ options[:host], options[:port] ].compact.join(":")
    end
end
