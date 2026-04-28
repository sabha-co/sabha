json.partial! "message", message: @message
json.mentionees @message.mentionees do |user|
  json.id user.id
  json.name user.name
end
