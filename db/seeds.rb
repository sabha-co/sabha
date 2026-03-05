unless Rails.env.development?
  puts "WARN: Seeding is just for development!"
  return
end

require "active_support/testing/time_helpers"
include ActiveSupport::Testing::TimeHelpers

# Seed DSL

def seed(name)
  print "  #{name}…"
  elapsed = Benchmark.realtime { require_relative "seeds/#{name}" }
  puts " #{elapsed.round(2)} sec"
end

def find_or_create_user(full_name, email_address, role: :member)
  User.find_or_create_by!(email_address: email_address) do |user|
    user.name = full_name
    user.role = role
    user.password = "password"
    user.verified_at = Time.current
  end
end

def post_message(room, creator, body, at: Time.current)
  travel_to(at) do
    room.messages.create!(creator: creator, body: body, client_message_id: Random.uuid)
  end
end

def boost_message(message, booster, content = "🎉")
  message.boosts.create!(booster: booster, content: content)
end

def bookmark_message(message, user)
  Bookmark.create!(message: message, user: user)
end

# Spread timestamps across a period for realistic-looking data
module TimeHelpers
  def spread_times(count, over: 7.days)
    start = over.ago
    interval = over / count
    count.times.map { |i| start + (interval * i) + rand(interval) }
  end
end
include TimeHelpers

puts "\n--- Seeding..."

if Sabha.saas?
  seed "saas"
else
  seed "self_hosted"
end
