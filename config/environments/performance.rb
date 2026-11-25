require_relative "production"

Rails.application.configure do
  config.assume_ssl = false
  config.force_ssl  = false
  config.action_cable.disable_request_forgery_protection = true
  config.action_cable.url = nil # Let client determine WebSocket URL

  config.after_initialize do
    if defined?(Rails::Server) && User.none?
      Account.create!(name: "Sabha")

      password_digest = User.new(password: "password").password_digest
      users = (1..10000).map do |i|
        {
          name: "User #{i}",
          role: i == 1 ? :administrator : :member,
          email_address: "user#{i}@example.com",
          password_digest: password_digest
        }
      end
      User.insert_all(users)

      sessions = User.all.map do |user|
        {
          user_id: user.id,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                      "(KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36",
          ip_address: "127.0.0.1",
          last_active_at: Time.now,
          token: "a" * 19 + user.id.to_s.rjust(5, "0")
        }
      end
      Session.insert_all(sessions)

      creator_id = User.first.id

      channels = (0..200).map { |i| { name: "Channel #{i}", creator_id: creator_id, type: "Channels::Closed" } }
      Channel.insert_all(channels)

      Channel.all.each_with_index do |channel, index|
        user_ids = User.where("MOD(#{index}, id) = 0").ids
        memberships = user_ids.map { |user_id| { channel_id: channel.id, user_id: user_id } }
        Membership.insert_all(memberships)
      end
    end
  end
end
