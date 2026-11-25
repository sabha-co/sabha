module Slack
  class MessagesImporter
    SKIPPED_SUBTYPES = %w[channel_join channel_leave channel_purpose channel_topic].freeze

    def initialize(context)
      @context = context
    end

    def import
      @context.channel_map.each do |slack_channel_id, channel|
        import_for_channel(slack_channel_id, channel)
      end
    end

    private

    def import_for_channel(slack_channel_id, channel)
      channel_folder = find_channel_folder(slack_channel_id)
      unless channel_folder
        @context.log "Warning: No message folder found for channel #{slack_channel_id} (#{channel.name})"
        return
      end

      @context.log "Processing messages for ##{channel.name} from folder: #{channel_folder}/"

      message_files = @context.zip.entries.select do |entry|
        entry.name.start_with?("#{channel_folder}/") &&
          entry.name.end_with?(".json") &&
          entry.name != "#{channel_folder}/"
      end

      return if message_files.empty?

      message_files.sort_by(&:name).each do |entry|
        messages = JSON.parse(@context.zip.read(entry.name))
        messages.each { |msg| import_message(msg, channel) }
      rescue JSON::ParserError => e
        @context.log "Warning: Failed to parse #{entry.name}: #{e.message}"
      end
    end

    def import_message(msg, channel)
      return unless msg["type"] == "message"
      return if msg["subtype"].in?(SKIPPED_SUBTYPES)

      user = @context.user_map[msg["user"]]
      unless user
        @context.skipped_user_messages << msg["ts"] if msg["ts"]
        @context.log "Skipped message (unknown user #{msg['user']}): #{msg['text']&.truncate(50)}"
        return
      end

      client_message_id = "slack_#{msg['ts']}"

      existing_message = Message.find_by(client_message_id: client_message_id)
      if existing_message
        @context.message_map[msg["ts"]] = existing_message
        track_thread_reply(existing_message, msg, channel)
        return
      end

      body = @context.mention_converter.convert(msg["text"])
      return if body.blank?

      message = create_message(channel, user, body, client_message_id, msg["ts"])
      @context.message_map[msg["ts"]] = message

      track_thread_reply(message, msg, channel)
      import_reactions(msg["reactions"], message) if msg["reactions"]

      @context.increment(:messages)
      @context.log "Imported #{@context.stats[:messages]} messages..." if (@context.stats[:messages] % 500).zero?
    end

    def create_message(channel, user, body, client_message_id, slack_ts)
      timestamp = Time.at(slack_ts.to_f)

      message = Message.new(
        channel: channel,
        creator: user,
        body: body,
        client_message_id: client_message_id
      )
      message.save!(validate: false)
      message.update_columns(created_at: timestamp, updated_at: timestamp)
      message
    end

    def track_thread_reply(message, msg, channel)
      return unless msg["thread_ts"].present? && msg["thread_ts"] != msg["ts"]

      @context.thread_replies << {
        message: message,
        thread_ts: msg["thread_ts"],
        channel: channel
      }
    end

    def import_reactions(reactions, message)
      reactions.each do |reaction|
        emoji = EmojiConverter.convert(reaction["name"])

        (reaction["users"] || []).each do |user_id|
          user = @context.user_map[user_id]
          next unless user
          next if message.boosts.exists?(booster: user, content: emoji)

          boost = Boost.new(message: message, booster: user, content: emoji)
          boost.save!(validate: false)
          boost.update_columns(created_at: message.created_at)

          @context.increment(:boosts)
        end
      end
    end

    def find_channel_folder(slack_channel_id)
      %w[channels.json groups.json].each do |manifest|
        next unless @context.file_exists?(manifest)

        entity = @context.parse_json(manifest).find { |e| e["id"] == slack_channel_id }
        folder = entity&.dig("name")
        return folder if folder && @context.folder_exists?(folder)
      end

      if @context.file_exists?("dms.json")
        dm = @context.parse_json("dms.json").find { |d| d["id"] == slack_channel_id }
        return dm["id"] if dm && @context.folder_exists?(dm["id"])
      end

      nil
    end
  end
end
