json.results @messages do |message|
  json.id message.id
  json.creator do
    json.id message.creator.id
    json.name message.creator.name
  end
  json.body do
    json.html message.body.body.to_s
    json.plain message.plain_text_body
  end
  json.channel do
    json.id message.channel.id
    json.name message.channel.name
  end
  json.created_at message.created_at.iso8601
end
json.has_more @has_more
json.next_cursor @next_cursor
