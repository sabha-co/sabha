# rails generate:demo
# rails generate:demo:max

namespace :generate do
  namespace :demo do
    desc "Generate MAX demo: 500 users, 2000 messages, all features"
    task max: :environment do
      require "faker"

      puts "🔥 MAXIMUM DEMO MODE"
      puts "   500 users, 2000+ messages, all features"
      puts ""

      puts "🧹 Cleaning existing data..."
      MaxDemo.clean_database

      puts "🏷️  Creating badges..."
      badges = MaxDemo.create_badges

      puts "👥 Creating 500 users..."
      users = MaxDemo.create_users(badges)

      puts "🏠 Creating rooms..."
      rooms = MaxDemo.create_rooms(users)

      puts "💬 Generating 2000+ messages..."
      MaxDemo.create_messages(rooms, users)

      puts "🧵 Creating threads..."
      MaxDemo.create_threads(rooms, users)

      puts "🔥 Adding boosts..."
      MaxDemo.create_boosts(users)

      puts "🔖 Adding bookmarks..."
      MaxDemo.create_bookmarks(users)

      puts "🚫 Creating blocked users..."
      MaxDemo.create_blocks(users)

      puts "⛔ Banning users..."
      MaxDemo.ban_users(users)

      puts "😴 Deactivating users..."
      MaxDemo.deactivate_users(users)

      puts "🔥 Setting streaks..."
      MaxDemo.set_streaks

      puts ""
      puts "✅ MAX demo environment ready!"
      puts ""
      puts "📊 Summary:"
      puts "   Users: #{User.count} (#{User.active.count} active, #{User.where(status: :deactivated).count} deactivated, #{User.where(status: :banned).count} banned)"
      puts "   Streaks: #{User.where('current_streak > 0').count} users with streaks (max: #{User.maximum(:current_streak)} days)"
      puts "   Badges: #{Badge.count}"
      puts "   Open Rooms: #{Rooms::Open.count}"
      puts "   Closed Rooms: #{Rooms::Closed.count}"
      puts "   Direct Messages: #{Rooms::Direct.count}"
      puts "   Threads: #{Rooms::Thread.count}"
      puts "   Messages: #{Message.count} (#{Message.where(active: false).count} soft-deleted)"
      puts "   Boosts: #{Boost.count}"
      puts "   Bookmarks: #{Bookmark.count}"
      puts "   Blocks: #{Block.count}"
      puts "   Bans: #{Ban.count}"
      puts ""
      puts "🔑 Login credentials (password: 'password'):"
      puts "   Admin: admin@campfirecloud.com"
      puts "   Mod:   mod@campfirecloud.com"
      puts "   User:  user@campfirecloud.com"
    end
  end

  module MaxDemo
    extend self

    BOOST_EMOJIS = %w[👍 ❤️ 🔥 😂 🎉 👏 💯 🙌 ✨ 🚀 💪 🤔 😍 🙏 👀].freeze

    # Pre-generated message templates for speed
    CHAT_MESSAGES = [
      "Just shipped a new feature! 🚀",
      "Anyone else working late tonight?",
      "Great discussion in the meeting today",
      "Has anyone tried the new update?",
      "Quick question about the API...",
      "Thanks for the help earlier! 🙏",
      "This is exactly what I needed",
      "Working on something cool, will share soon",
      "Love this community!",
      "Monday motivation ☕",
      "Finally fixed that bug 🎉",
      "Who's up for a code review?",
      "Just learned something new today",
      "This thread is gold",
      "Bookmarking this for later",
      "+1",
      "👍",
      "💯",
      "Great point!",
      "Agree completely",
      "Interesting perspective",
      "Never thought of it that way",
      "Can someone explain this?",
      "Here's my take on it...",
      "Following up on this",
      "Any updates?",
      "Works for me!",
      "Let me check and get back",
      "Perfect, thanks!",
      "This is helpful"
    ].freeze

    def clean_database
      # Order matters due to foreign keys
      Boost.delete_all
      Bookmark.delete_all
      Mention.delete_all
      Block.delete_all
      ActionText::RichText.delete_all
      Message.where(room_id: Rooms::Thread.select(:id)).delete_all
      Membership.where(room_id: Rooms::Thread.select(:id)).delete_all
      Rooms::Thread.delete_all
      Message.delete_all
      Membership.delete_all
      Room.delete_all
      Session.delete_all
      AuthToken.delete_all
      Ban.delete_all
      User.delete_all
      Badge.delete_all

      Account.first_or_create!(name: "Campfire")
    end

    def create_badges
      now = Time.current
      Badge.insert_all([
        { name: "Founder", color: "#7C3AED", icon: "⭐", created_at: now, updated_at: now },
        { name: "Mod", color: "#2563EB", icon: "🛡️", created_at: now, updated_at: now },
        { name: "Mentor", color: "#059669", icon: "🎓", created_at: now, updated_at: now },
        { name: "Contrib", color: "#D97706", icon: "🔧", created_at: now, updated_at: now },
        { name: "Early", color: "#DC2626", icon: "🐦", created_at: now, updated_at: now },
        { name: "Pro", color: "#7C3AED", icon: "💎", created_at: now, updated_at: now }
      ])
      Badge.all.to_a
    end

    def create_users(badges)
      password_digest = BCrypt::Password.create("password")
      now = Time.current
      badge_ids = badges.index_by(&:name)

      # Special users first
      special_users = [
        { name: "Admin User", email_address: "admin@campfirecloud.com", role: 2, bio: "Community administrator", badge_id: badge_ids["Founder"]&.id, current_streak: 45 },
        { name: "Moderator", email_address: "mod@campfirecloud.com", role: 1, bio: "Community moderator", badge_id: badge_ids["Mod"]&.id, current_streak: 12 },
        { name: "Regular User", email_address: "user@campfirecloud.com", role: 0, bio: "Just a regular member", badge_id: nil, current_streak: 3 }
      ]

      # Pre-generate all user data
      print "   Generating user data..."
      user_records = special_users.map do |u|
        {
          name: u[:name],
          email_address: u[:email_address],
          password_digest: password_digest,
          role: u[:role],
          bio: u[:bio],
          twitter_url: nil,
          linkedin_url: nil,
          badge_id: u[:badge_id],
          current_streak: u[:current_streak],
          verified_at: now,
          created_at: now,
          updated_at: now
        }
      end

      # Generate 497 faker users in memory first
      497.times do
        # Streak distribution: 60% zero, 20% short (1-7), 15% medium (8-30), 5% long (31-100)
        r = rand
        streak = if r < 0.6
                   0
        elsif r < 0.8
                   rand(1..7)
        elsif r < 0.95
                   rand(8..30)
        else
                   rand(31..100)
        end
        badge_id = rand < 0.1 ? badges.sample.id : nil

        user_records << {
          name: Faker::Name.name,
          email_address: Faker::Internet.unique.email,
          password_digest: password_digest,
          role: rand < 0.02 ? 1 : 0,
          bio: rand < 0.7 ? Faker::Company.catch_phrase : nil,
          twitter_url: rand < 0.2 ? "https://x.com/#{Faker::Internet.username}" : nil,
          linkedin_url: rand < 0.15 ? "https://linkedin.com/in/#{Faker::Internet.username}" : nil,
          badge_id: badge_id,
          current_streak: streak,
          verified_at: now,
          created_at: now - rand(1..90).days,
          updated_at: now
        }
      end
      puts " done!"

      # Bulk insert all users
      print "   Inserting users..."
      User.insert_all(user_records)
      puts " done!"

      User.order(:id).to_a
    end

    def create_rooms(users)
      admin = users.first
      rooms = { open: [], closed: [], direct: [] }

      # Open rooms
      open_rooms_data = [
        { name: "General", slug: "general" },
        { name: "Introductions", slug: "introductions" },
        { name: "Random", slug: "random" },
        { name: "Show & Tell", slug: "show-and-tell" },
        { name: "Help & Support", slug: "help" },
        { name: "Announcements", slug: "announcements" },
        { name: "Feedback", slug: "feedback" },
        { name: "Off-Topic", slug: "off-topic" }
      ]

      open_rooms_data.each do |data|
        rooms[:open] << Rooms::Open.create!(
          name: data[:name],
          slug: data[:slug],
          creator: admin
        )
      end
      puts "   Created #{rooms[:open].count} open rooms"

      # Closed rooms with varying membership sizes
      closed_rooms_data = [
        { name: "Founders Circle", slug: "founders", size: 25 },
        { name: "Backend Guild", slug: "backend", size: 100 },
        { name: "Frontend Crew", slug: "frontend", size: 90 },
        { name: "Design Team", slug: "design", size: 50 },
        { name: "DevOps", slug: "devops", size: 40 },
        { name: "Book Club", slug: "books", size: 75 },
        { name: "Fitness Buddies", slug: "fitness", size: 60 },
        { name: "Music Lovers", slug: "music", size: 45 },
        { name: "Gaming Squad", slug: "gaming", size: 100 },
        { name: "Mentorship", slug: "mentorship", size: 30 }
      ]

      closed_rooms_data.each do |data|
        room = Rooms::Closed.create!(
          name: data[:name],
          slug: data[:slug],
          creator: admin
        )
        members = users.sample(data[:size])
        members = ([ admin ] + members).uniq
        room.memberships.grant_to(members)
        rooms[:closed] << room
      end
      puts "   Created #{rooms[:closed].count} closed rooms"

      # Direct messages - create many DM conversations
      print "   Creating DMs: "

      # Ensure special users have DMs
      special_users = users.first(3) # admin, mod, user
      other_users = users[3..]

      # DMs between special users
      special_users.combination(2).each do |pair|
        Current.user = pair.first
        begin
          dm = Rooms::Direct.create_for({}, users: pair)
          rooms[:direct] << dm
          add_dm_messages(dm, pair)
        rescue ActiveRecord::RecordInvalid
          nil
        end
      end

      # DMs from special users to random members
      special_users.each do |special|
        rand(3..6).times do
          other = other_users.sample
          Current.user = special
          begin
            dm = Rooms::Direct.create_for({}, users: [ special, other ])
            rooms[:direct] << dm
            add_dm_messages(dm, [ special, other ])
          rescue ActiveRecord::RecordInvalid
            nil
          end
        end
      end

      # Random DMs between other users
      60.times do |i|
        participants = other_users.sample(rand(2..4))
        Current.user = participants.first
        begin
          dm = Rooms::Direct.create_for({}, users: participants)
          rooms[:direct] << dm
        rescue ActiveRecord::RecordInvalid
          nil
        end
        print "." if (i % 30).zero?
      end
      Current.user = nil
      puts " done! (#{rooms[:direct].count} DMs)"

      rooms
    end

    def add_dm_messages(dm, participants)
      base_time = rand(7..21).days.ago
      dm_messages = [
        "Hey! How's it going?",
        "Got a minute to chat?",
        "Sure, what's up?",
        "Just wanted to follow up",
        "Sounds good!",
        "Let me know when you're free",
        "👍",
        "Thanks!",
        "Perfect"
      ]

      rand(4..8).times do |i|
        user = participants.sample
        body = dm_messages.sample
        time_offset = (i * rand(5..60)).minutes

        begin
          Message.create!(
            room: dm,
            creator: user,
            body: body,
            created_at: base_time + time_offset,
            client_message_id: SecureRandom.uuid
          )
        rescue ActiveRecord::RecordInvalid
          nil
        end
      end
    end

    def create_messages(rooms, users)
      all_rooms = rooms[:open] + rooms[:closed]
      message_count = 0

      print "   Generating messages: "

      # Distribute messages across open and closed rooms
      all_rooms.each do |room|
        room_users = room.users.to_a
        next if room_users.empty?

        count = rand(80..150)
        base_time = rand(30..60).days.ago
        user_ids = room_users.map(&:id)
        admin_ids = room_users.select(&:administrator?).map(&:id)

        count.times do |i|
          user = room_users.sample
          time_offset = (i * rand(3..30)).minutes
          body = CHAT_MESSAGES.sample

          # Add mentions occasionally
          if rand < 0.1 && room_users.length > 1
            mentioned = (room_users - [ user ]).sample
            body = "@#{mentioned.name.split.first.downcase} #{body}"
          end

          # Admin can mention everyone in open rooms
          if rand < 0.02 && user.administrator? && room.is_a?(Rooms::Open)
            body = "@everyone #{body}"
          end

          begin
            Message.create!(
              room: room,
              creator: user,
              body: body,
              created_at: base_time + time_offset,
              client_message_id: SecureRandom.uuid
            )
            message_count += 1
          rescue ActiveRecord::RecordInvalid
            nil
          end
        end
        print "."
      end

      # Add ~500 messages to DMs
      # Add messages to DMs without special user messages
      dm_bodies = [ "Hey!", "What's up?", "Sounds good", "👍", "Thanks!", "Perfect", "Got it", "Let me know" ]
      rooms[:direct].each do |dm|
        dm_users = dm.users.to_a
        next if dm_users.length < 2

        base_time = rand(14..30).days.ago
        rand(8..20).times do |i|
          user = dm_users.sample
          time_offset = (i * rand(5..60)).minutes

          begin
            Message.create!(
              room: dm,
              creator: user,
              body: dm_bodies.sample,
              created_at: base_time + time_offset,
              client_message_id: SecureRandom.uuid
            )
            message_count += 1
          rescue ActiveRecord::RecordInvalid
            nil
          end
        end
      end

      puts " done! (#{message_count} messages)"
    end

    THREAD_STARTERS = [
      "Let's discuss this further!",
      "Expanding on this point...",
      "Great question! Here's more context:",
      "I have thoughts on this 💭",
      "Jumping in with some details"
    ].freeze

    THREAD_REPLIES = [
      "Good point!",
      "I agree completely",
      "Interesting perspective",
      "To add to this...",
      "+1",
      "👍",
      "This! Exactly!",
      "💯",
      "🔥",
      "Makes sense",
      "Thanks for sharing"
    ].freeze

    def create_threads(rooms, users)
      # Get messages that can have threads
      threadable = Message.joins(:room)
                          .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                          .where("messages.created_at < ?", 3.days.ago)
                          .order("RANDOM()")
                          .limit(30)

      print "   Creating threads: "
      thread_count = 0

      threadable.each do |parent|
        room_users = parent.room.users.to_a
        next if room_users.length < 2

        creator = (room_users - [ parent.creator ]).sample || room_users.sample
        Current.user = creator

        begin
          thread = Rooms::Thread.create_for(
            { parent_message_id: parent.id },
            users: room_users
          )

          base_time = parent.created_at + rand(30..180).minutes

          # First message
          Message.create!(
            room: thread,
            creator: creator,
            body: THREAD_STARTERS.sample,
            created_at: base_time,
            client_message_id: SecureRandom.uuid
          )

          # Replies
          rand(3..8).times do |i|
            user = room_users.sample
            time_offset = (i + 1) * rand(5..30).minutes

            Message.create!(
              room: thread,
              creator: user,
              body: THREAD_REPLIES.sample,
              created_at: base_time + time_offset,
              client_message_id: SecureRandom.uuid
            )
          end

          thread_count += 1
          print "."
        rescue ActiveRecord::RecordInvalid
          nil
        end
      end

      Current.user = nil
      puts " done! (#{thread_count} threads)"
    end

    def create_boosts(users)
      messages = Message.joins(:room)
                        .where.not(rooms: { type: "Rooms::Direct" })
                        .where(active: true)
                        .order("RANDOM()")
                        .limit(200)

      now = Time.current
      boost_records = []

      messages.each do |message|
        room_user_ids = message.room.user_ids - [ message.creator_id ]
        next if room_user_ids.empty?

        booster_ids = room_user_ids.sample(rand(1..4))
        booster_ids.each do |booster_id|
          boost_records << {
            message_id: message.id,
            booster_id: booster_id,
            content: BOOST_EMOJIS.sample,
            created_at: message.created_at + rand(1..120).minutes,
            updated_at: now
          }
        end
      end

      # Bulk insert boosts
      Boost.insert_all(boost_records) if boost_records.any?
      puts "   Created #{boost_records.count} boosts"
    end

    def create_bookmarks(users)
      now = Time.current
      bookmark_records = []

      # Only ~20% of users bookmark things
      bookmarking_users = users.sample(users.count / 5)

      bookmarking_users.each do |user|
        message_ids = Message.where(room_id: user.room_ids, active: true)
                             .order("RANDOM()")
                             .limit(rand(1..3))
                             .pluck(:id)

        message_ids.each do |message_id|
          bookmark_records << {
            user_id: user.id,
            message_id: message_id,
            created_at: now - rand(1..180).minutes,
            updated_at: now
          }
        end
      end

      Bookmark.insert_all(bookmark_records) if bookmark_records.any?
      puts "   Created #{bookmark_records.count} bookmarks"
    end

    def create_blocks(users)
      now = Time.current
      regular_users = users.reject { |u| u.email_address.include?("campfirecloud.com") }
      block_records = []

      15.times do
        blocker, blocked = regular_users.sample(2)
        next if blocker == blocked
        next if block_records.any? { |b| b[:blocker_id] == blocker.id && b[:blocked_id] == blocked.id }

        block_records << {
          blocker_id: blocker.id,
          blocked_id: blocked.id,
          created_at: now,
          updated_at: now
        }
      end

      Block.insert_all(block_records) if block_records.any?
      puts "   Created #{block_records.count} blocks"
    end

    def ban_users(users)
      bannable = users.reject { |u| u.email_address.include?("campfirecloud.com") }
      to_ban = bannable.sample(15)
      now = Time.current

      # Bulk create sessions with random IPs
      session_records = []
      to_ban.each do |user|
        rand(1..2).times do
          created = now - rand(1..30).days
          session_records << {
            user_id: user.id,
            ip_address: "#{rand(1..223)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(1..254)}",
            user_agent: "Mozilla/5.0 Demo Browser",
            token: SecureRandom.urlsafe_base64(32),
            created_at: created,
            updated_at: now,
            last_active_at: created
          }
        end
      end
      Session.insert_all(session_records) if session_records.any?

      # Now ban each user
      to_ban.each do |user|
        user.reload # Reload to get sessions
        user.ban
        user.remove_banned_content
      end
      puts "   Banned #{to_ban.count} users"
    end

    def deactivate_users(users)
      # Deactivate some users (not special accounts or banned)
      deactivatable = users.reject do |u|
        u.email_address.include?("campfirecloud.com") || u.banned?
      end
      to_deactivate = deactivatable.sample(25)

      to_deactivate.each(&:deactivate)
      puts "   Deactivated #{to_deactivate.count} users"
    end

    def set_streaks
      # Set streaks at the end to avoid being overwritten by message callbacks
      # Special users keep their fixed streaks
      User.where(email_address: "admin@campfirecloud.com").update_all(current_streak: 45)
      User.where(email_address: "mod@campfirecloud.com").update_all(current_streak: 12)
      User.where(email_address: "user@campfirecloud.com").update_all(current_streak: 3)

      # Random streaks for other users: 60% zero, 20% short, 15% medium, 5% long
      other_users = User.where.not(email_address: %w[admin@campfirecloud.com mod@campfirecloud.com user@campfirecloud.com])
      other_users.find_each do |user|
        r = rand
        streak = if r < 0.6
                   0
        elsif r < 0.8
                   rand(1..7)
        elsif r < 0.95
                   rand(8..30)
        else
                   rand(31..100)
        end
        user.update_column(:current_streak, streak)
      end
      puts "   Set streaks for #{User.count} users"
    end
  end

  desc "Generate a complete demo environment with users, rooms, and messages"
  task demo: :environment do
    require "faker"

    # Use simple password locally, random password in production
    demo_password = Rails.env.local? ? "password" : SecureRandom.alphanumeric(12)

    puts "🧹 Cleaning existing data..."
    clean_database

    puts "👥 Creating demo users..."
    users = create_users(demo_password)

    puts "🏠 Creating rooms..."
    rooms = create_rooms(users)

    puts "💬 Generating messages..."
    create_messages(rooms, users)

    puts "🧵 Creating threads..."
    create_threads(rooms, users)

    puts "🔥 Adding boosts..."
    create_boosts(users)

    puts "🔖 Adding bookmarks..."
    create_bookmarks(users)

    puts "✅ Demo environment ready!"
    puts ""
    puts "📊 Summary:"
    puts "   Users: #{User.count}"
    puts "   Rooms: #{Room.where(type: %w[Rooms::Open Rooms::Closed]).count} (+ #{Rooms::Direct.count} DMs, #{Rooms::Thread.count} threads)"
    puts "   Messages: #{Message.count}"
    puts "   Boosts: #{Boost.count}"
    puts "   Bookmarks: #{Bookmark.count}"
    puts ""
    puts "🔑 Login credentials:"
    puts "   Email: admin@campfirecloud.com"
    puts "   Password: #{demo_password}"
  end

  desc "Generate messages in a specific room (default: Lobby)"
  task lines: :environment do
    room = Room.find_by(name: "Lobby")
    users = User.all

    1.upto(500) do |i|
      room.messages.create! \
        body: "Message #{i}",
        user: users.sample,
        created_at: 1.day.ago + i.minutes
    end
  end

  desc "Add more messages to existing demo (without wiping data)"
  task more_messages: :environment do
    require "faker"

    users = User.where(role: %w[member administrator]).to_a
    rooms = Room.without_directs.to_a

    if users.empty? || rooms.empty?
      puts "❌ No users or rooms found. Run `rake generate:demo` first."
      exit 1
    end

    puts "💬 Adding more messages..."
    rooms.each do |room|
      room_users = room.users.to_a
      next if room_users.empty?

      rand(20..50).times do
        create_single_message(room, room_users.sample, users)
      end
    end

    puts "✅ Added more messages. Total: #{Message.count}"
  end

  private

  def clean_database
    # Order matters due to foreign keys
    # 1. Delete reactions/references to messages
    Boost.delete_all
    Bookmark.delete_all
    Mention.delete_all
    ActionText::RichText.delete_all
    # 2. Delete messages inside threads (before deleting threads)
    Message.where(room_id: Rooms::Thread.select(:id)).delete_all
    # 3. Delete thread memberships and threads (threads have FK to parent_message)
    Membership.where(room_id: Rooms::Thread.select(:id)).delete_all
    Rooms::Thread.delete_all
    # 4. Now safe to delete remaining messages and rooms
    Message.delete_all
    Membership.delete_all
    Room.delete_all
    Session.delete_all
    AuthToken.delete_all
    Ban.delete_all
    User.delete_all

    # Ensure we have an account
    Account.first_or_create!(name: "Campfire")
  end

  def create_users(password)
    # Admin user
    admin = User.create!(
      name: "Admin User",
      email_address: "admin@campfirecloud.com",
      password: password,
      password_confirmation: password,
      role: "administrator",
      bio: "Community administrator",
      verified_at: Time.current
    )

    # Regular users with varied profiles
    user_profiles = [
      { name: "Sarah Chen", bio: "Product designer & coffee enthusiast ☕", twitter_url: "https://x.com/sarahchen" },
      { name: "Marcus Johnson", bio: "Full-stack developer. Building cool stuff.", linkedin_url: "https://linkedin.com/in/marcusj" },
      { name: "Emily Rodriguez", bio: "UX researcher | Always curious", twitter_url: "https://x.com/emilyux" },
      { name: "David Kim", bio: "Engineering lead @startup", linkedin_url: "https://linkedin.com/in/davidkim" },
      { name: "Priya Patel", bio: "Indie hacker. Shipped 3 products this year 🚀" },
      { name: "James Wilson", bio: "Backend engineer. Rust & Go.", twitter_url: "https://x.com/jameswdev" },
      { name: "Aisha Mohammed", bio: "Mobile dev | SwiftUI enthusiast", linkedin_url: "https://linkedin.com/in/aishadev" },
      { name: "Carlos Garcia", bio: "DevOps & Cloud | AWS certified" },
      { name: "Lisa Thompson", bio: "Technical writer & documentation nerd 📝" },
      { name: "Alex Nakamura", bio: "Startup founder. 2x exit. Angel investor." },
      { name: "Rachel Green", bio: "Junior dev learning in public 🌱" },
      { name: "Michael Brown", bio: "15y in tech. Mentoring is my passion." },
      { name: "Sophie Martin", bio: "Data scientist | ML/AI", twitter_url: "https://x.com/sophieml" },
      { name: "Hassan Ali", bio: "Security engineer. Breaking things (ethically)." },
      { name: "Nina Kowalski", bio: "Product manager turned founder" }
    ]

    users = [ admin ]

    user_profiles.each_with_index do |profile, i|
      users << User.create!(
        name: profile[:name],
        email_address: "user#{i + 1}@example.com",
        password: password,
        password_confirmation: password,
        role: "member",
        bio: profile[:bio],
        twitter_url: profile[:twitter_url],
        linkedin_url: profile[:linkedin_url],
        verified_at: Time.current,
        created_at: rand(1..90).days.ago
      )
    end

    users
  end

  def create_rooms(users)
    admin = users.first
    rooms = {}

    # Open rooms (everyone gets auto-membership)
    open_rooms = [
      { name: "General", slug: "general" },
      { name: "Introductions", slug: "introductions" },
      { name: "Random", slug: "random" },
      { name: "Show & Tell", slug: "show-and-tell" },
      { name: "Help & Support", slug: "help" }
    ]

    open_rooms.each do |room_data|
      rooms[room_data[:slug]] = Rooms::Open.create!(
        name: room_data[:name],
        slug: room_data[:slug],
        creator: admin
      )
    end

    # Closed rooms (invite only)
    closed_rooms = [
      { name: "Founders Circle", slug: "founders", members: users.sample(6) },
      { name: "Backend Guild", slug: "backend", members: users.sample(5) },
      { name: "Design Crew", slug: "design", members: users.sample(4) },
      { name: "Book Club", slug: "books", members: users.sample(7) }
    ]

    closed_rooms.each do |room_data|
      room = Rooms::Closed.create!(
        name: room_data[:name],
        slug: room_data[:slug],
        creator: admin
      )
      room.memberships.grant_to([ admin ] + room_data[:members])
      rooms[room_data[:slug]] = room
    end

    # Direct messages (1-on-1 conversations)
    dm_pairs = users.combination(2).to_a.sample(8)
    dm_pairs.each do |pair|
      Current.user = pair.first
      dm = Rooms::Direct.create_for({}, users: pair)
      rooms["dm_#{pair.map(&:id).join('_')}"] = dm
    end

    # Multi-user DM (group conversation)
    group_dm_users = users.sample(4)
    Current.user = group_dm_users.first
    group_dm = Rooms::Direct.create_for({}, users: group_dm_users)
    rooms["group_dm"] = group_dm

    # Add messages to group DM
    base_time = rand(3..7).days.ago
    group_dm_messages = [
      "Hey everyone! Thought we should have a group chat 👋",
      "Great idea! This will be easier than individual messages",
      "Agreed! So what's everyone working on?",
      "Building a new feature for #{Faker::App.name}",
      "Nice! I'm debugging some #{Faker::Hacker.noun} issues",
      "Let's sync up later this week?"
    ]
    group_dm_messages.each_with_index do |body, i|
      user = group_dm_users[i % group_dm_users.length]
      Message.create!(
        room: group_dm,
        creator: user,
        body: body,
        created_at: base_time + (i * rand(5..30)).minutes,
        client_message_id: SecureRandom.uuid
      )
    end

    Current.user = nil

    rooms
  end

  def create_messages(rooms, users)
    # Conversation templates for more realistic chat
    general_topics = [
      -> { Faker::Lorem.sentence(word_count: rand(5..15)) },
      -> { "Has anyone tried #{Faker::App.name}? Looking for recommendations." },
      -> { "#{Faker::Hacker.say_something_smart}" },
      -> { "TIL: #{Faker::ChuckNorris.fact.gsub('Chuck Norris', 'a good developer')}" },
      -> { "Working on #{Faker::App.name} today. #{%w[Excited Nervous Motivated Tired].sample}!" },
      -> { "Quick question: #{Faker::Lorem.question}" },
      -> { "🎉 Just shipped #{Faker::App.name} v#{Faker::App.version}!" },
      -> { "Anyone else dealing with #{Faker::Hacker.noun} issues?" },
      -> { "Pro tip: #{Faker::Lorem.sentence(word_count: rand(8..12))}" },
      -> { "#{%w[Monday Tuesday Wednesday Thursday Friday].sample} vibes ☕" },
      -> { "Great article on #{Faker::ProgrammingLanguage.name}: #{Faker::Lorem.sentence}" },
      -> { "#{Faker::Quote.famous_last_words}" },
      -> { "Debugging #{Faker::Hacker.noun} for the past #{rand(2..5)} hours... 😅" },
      -> { "Hot take: #{Faker::Lorem.sentence(word_count: rand(6..10))}" },
      -> { "Need feedback on this approach: #{Faker::Lorem.paragraph(sentence_count: 2)}" }
    ]

    intro_messages = [
      ->(user) { "Hey everyone! 👋 I'm #{user.name.split.first}. #{user.bio || 'Excited to be here!'}" },
      ->(user) { "Hi! Just joined. Looking forward to connecting with everyone here." },
      ->(user) { "New here! Been in tech for #{rand(1..15)} years. #{Faker::Lorem.sentence}" }
    ]

    help_messages = [
      -> { "Can someone help me with #{Faker::ProgrammingLanguage.name}? #{Faker::Lorem.question}" },
      -> { "Getting this error: `#{Faker::Hacker.abbreviation}_#{rand(100..999)}`. Any ideas?" },
      -> { "What's the best way to #{Faker::Hacker.verb} a #{Faker::Hacker.noun}?" },
      -> { "Documentation says X but I'm seeing Y. Anyone else?" },
      -> { "Solved my issue! The problem was #{Faker::Lorem.sentence(word_count: rand(5..10))}" }
    ]

    show_tell_messages = [
      -> { "Just launched #{Faker::App.name}! Check it out: #{Faker::Internet.url}" },
      -> { "Side project update: #{Faker::Lorem.paragraph(sentence_count: 2)}" },
      -> { "Built this over the weekend: #{Faker::Lorem.sentence}. Feedback welcome! 🚀" },
      -> { "Finally hit #{rand(100..10000)} users on #{Faker::App.name}! 🎉" },
      -> { "Open sourced my #{Faker::Hacker.noun} tool: #{Faker::Internet.url(host: 'github.com')}" }
    ]

    # Generate messages for each room
    rooms.each do |slug, room|
      next if room.direct? # DMs handled separately

      room_users = room.users.to_a
      message_count = case slug
      when "general" then rand(80..120)
      when "introductions" then rand(15..25)
      when "random" then rand(40..60)
      when "show-and-tell" then rand(20..35)
      when "help" then rand(30..50)
      else rand(20..40)
      end

      templates = case slug
      when "introductions" then intro_messages
      when "help" then help_messages
      when "show-and-tell" then show_tell_messages
      else general_topics
      end

      # Generate messages spread over time
      base_time = rand(14..30).days.ago

      message_count.times do |i|
        user = room_users.sample
        time_offset = (i * rand(5..60)).minutes

        template = templates.sample
        body = template.arity == 1 ? template.call(user) : template.call

        # Occasionally add mentions
        if rand < 0.15 && room_users.length > 1
          mentioned_user = (room_users - [ user ]).sample
          body = "@#{mentioned_user.name.split.first.downcase} #{body}"
        end

        # Occasionally add replies/reactions
        body = "#{%w[+1 👍 This! Agree! 💯 Nice!].sample}" if rand < 0.08

        create_message_safely(room, user, body, base_time + time_offset)
      end

      print "."
    end

    # Generate DM conversations
    rooms.select { |_, r| r.direct? }.each do |_, dm|
      dm_users = dm.users.to_a
      next if dm_users.length < 2

      base_time = rand(7..21).days.ago

      rand(10..30).times do |i|
        user = dm_users.sample
        time_offset = (i * rand(10..120)).minutes

        body = [
          -> { "Hey! #{Faker::Lorem.sentence}" },
          -> { Faker::Lorem.sentence(word_count: rand(3..12)) },
          -> { "Quick question: #{Faker::Lorem.sentence}" },
          -> { "#{%w[Sounds good! Perfect Thanks! Got it 👍].sample}" },
          -> { "Let me check and get back to you" },
          -> { "#{Faker::Lorem.paragraph(sentence_count: 1)}" }
        ].sample.call

        create_message_safely(dm, user, body, base_time + time_offset)
      end
    end

    puts " done!"
  end

  def create_message_safely(room, user, body, created_at)
    Message.create!(
      room: room,
      creator: user,
      body: body,
      created_at: created_at,
      client_message_id: SecureRandom.uuid
    )
  rescue ActiveRecord::RecordInvalid => e
    # Skip messages that fail validation (e.g., blocked users in DMs)
    nil
  end

  def create_single_message(room, user, all_users)
    bodies = [
      Faker::Lorem.sentence(word_count: rand(5..15)),
      "#{Faker::Hacker.say_something_smart}",
      "Working on #{Faker::App.name}",
      Faker::Quote.famous_last_words,
      "Quick update: #{Faker::Lorem.sentence}"
    ]

    create_message_safely(room, user, bodies.sample, rand(1..48).hours.ago)
  end

  def create_threads(rooms, users)
    thread_starters = [
      -> { "This deserves its own thread - let's discuss!" },
      -> { "Expanding on this point..." },
      -> { "Great question! Let me elaborate..." },
      -> { "I have some thoughts on this" },
      -> { "Let's take this conversation deeper" }
    ]

    thread_replies = [
      -> { Faker::Lorem.sentence(word_count: rand(5..15)) },
      -> { "Good point! #{Faker::Lorem.sentence}" },
      -> { "I agree. #{Faker::Lorem.sentence(word_count: rand(4..10))}" },
      -> { "Interesting perspective. #{Faker::Lorem.sentence}" },
      -> { "To add to this: #{Faker::Lorem.sentence}" },
      -> { "#{%w[+1 👍 This! Exactly! 💯].sample}" }
    ]

    # Pick some messages from non-DM rooms to start threads on
    threadable_messages = Message.joins(:room)
                                  .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                                  .where("messages.created_at < ?", 2.days.ago)
                                  .order("RANDOM()")
                                  .limit(8)

    threadable_messages.each do |parent_message|
      room_users = parent_message.room.users.to_a
      next if room_users.length < 2

      thread_creator = (room_users - [ parent_message.creator ]).sample || room_users.sample
      Current.user = thread_creator

      # Create the thread
      thread = Rooms::Thread.create_for(
        { parent_message_id: parent_message.id },
        users: room_users
      )

      # Add the first message (why thread was started)
      base_time = parent_message.created_at + rand(30..180).minutes
      create_message_safely(thread, thread_creator, thread_starters.sample.call, base_time)

      # Add replies to the thread
      rand(3..10).times do |i|
        user = room_users.sample
        time_offset = (i + 1) * rand(5..30).minutes
        create_message_safely(thread, user, thread_replies.sample.call, base_time + time_offset)
      end

      print "."
    end

    Current.user = nil
    puts " done!"
  end

  def create_boosts(users)
    boost_emojis = %w[👍 ❤️ 🔥 😂 🎉 👏 💯 🙌 ✨ 🚀]

    messages = Message.joins(:room)
                      .where.not(rooms: { type: "Rooms::Direct" })
                      .order("RANDOM()")
                      .limit(50)

    messages.each do |message|
      boosters = (message.room.users.to_a - [ message.creator ]).sample(rand(1..4))
      boosters.each do |booster|
        Boost.create!(
          message: message,
          booster: booster,
          content: boost_emojis.sample,
          created_at: message.created_at + rand(1..60).minutes
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation
        nil
      end
    end
  end

  def create_bookmarks(users)
    users.each do |user|
      # Each user bookmarks a few random messages from rooms they're in
      user_messages = Message.where(room_id: user.room_ids)
                             .order("RANDOM()")
                             .limit(rand(3..8))

      user_messages.each do |message|
        Bookmark.create!(
          user: user,
          message: message,
          created_at: message.created_at + rand(1..120).minutes
        )
      rescue ActiveRecord::RecordInvalid
        nil
      end
    end
  end
end
