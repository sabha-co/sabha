json.bot_key        @bot.bot_key
json.webhook_secret @bot.webhook_secret
json.name           @bot.name
json.webhook_url    @bot.webhook_url
json.base_url       @base_url
json.api_base_url   "#{@base_url}/api/bots"
json.websocket_url  websocket_url_for_bot
json.rooms @bot.rooms.without_threads, partial: "api/bots/rooms/room", as: :room
