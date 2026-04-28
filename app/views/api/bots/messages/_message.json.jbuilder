json.id message.id
json.creator do
  json.id message.creator.id
  json.name message.creator.name
end
json.body do
  json.html message.body.body.to_s
  json.plain message.plain_text_body
end
if message.attachment?
  blob = message.attachment.blob
  json.attachment do
    json.url blob.url(expires_in: 1.hour)
    json.filename blob.filename.to_s
    json.content_type blob.content_type
    json.byte_size blob.byte_size
  end
else
  json.attachment nil
end
json.created_at message.created_at.iso8601
