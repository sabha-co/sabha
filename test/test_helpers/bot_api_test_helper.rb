module BotApiTestHelper
  def bot_headers(bot_or_token)
    token = bot_or_token.respond_to?(:bot_key) ? bot_or_token.bot_key : bot_or_token
    { "Authorization" => "Bearer #{token}" }
  end
end
