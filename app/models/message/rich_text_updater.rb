class Message::RichTextUpdater
  def self.update_room_links_in_quoted_messages(from:, to:)
    connection = ApplicationRecord.connection

    matching_pattern = "%/rooms/#{from}/@%\">#</a>%"
    old_room_part = "/rooms/#{from}/@"
    new_room_part = "/rooms/#{to}/@"

    # Use quote to safely escape string values for SQL
    connection.execute(<<~SQL)
    UPDATE action_text_rich_texts
    SET body = REPLACE(
      body,
      #{connection.quote(old_room_part)},
      #{connection.quote(new_room_part)}
    )
    WHERE name = 'body'
    AND record_type = 'Message'
    AND body LIKE #{connection.quote(matching_pattern)};
    SQL
  end
end
