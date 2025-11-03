class Message::RichTextUpdater
  def self.update_room_links_in_quoted_messages(from:, to:)
    matching_pattern = "%/rooms/#{from}/@%\">#</a>%"

    old_room_part = "/rooms/#{from}/@"
    new_room_part = "/rooms/#{to}/@"

    ActiveRecord::Base.connection.execute(<<~SQL)
    UPDATE action_text_rich_texts
    SET body = REPLACE(
      body,
      '#{old_room_part}',
      '#{new_room_part}'
    )
    WHERE name = 'body'
    AND record_type = 'Message'
    AND body LIKE '#{matching_pattern}';
    SQL
  end
end
