# rails generate:demo
# rails generate:demo:max
# BUNDLE_GEMFILE=Gemfile.saas SAAS=true bin/rails generate:demo:max

# Shared helpers for both MaxDemo and regular demo
module DemoHelpers
  extend self

  # ActionText mention HTML for proper @mentions
  def mention_html_for(user)
    %(<action-text-attachment sgid="#{user.attachable_sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment>)
  end

  # Create message body with proper ActionText mention
  def body_with_mention(user, text)
    "<div>#{mention_html_for(user)} #{text}</div>"
  end

  # Safe message creation with error handling
  def create_message_safely(room:, creator:, body:, created_at:)
    Message.create!(
      room: room,
      creator: creator,
      body: body,
      created_at: created_at,
      updated_at: created_at,
      client_message_id: SecureRandom.uuid
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Seed data is inserted "now" while messages carry a backdated created_at.
  # That leaves updated_at in the future (so Message#edited? is true for every
  # row) and posts each room's system events (created the room, member joins)
  # after the backdated chat, sorting them to the bottom. Fix both: align
  # updated_at, and pull each room's events to just before its first message.
  def normalize_seed_timestamps!
    Message.update_all("updated_at = created_at")

    Room.where.not(type: %w[Rooms::Direct Rooms::Thread Rooms::Post]).find_each do |room|
      earliest = room.messages.without_events.minimum(:created_at)
      next unless earliest

      base = earliest - 10.minutes
      room.messages.where.not(event: nil).order(:id).each_with_index do |event, index|
        timestamp = base + index.seconds
        event.update_columns(created_at: timestamp, updated_at: timestamp)
      end
    end
  end

  # Shared database cleanup (order matters due to foreign keys)
  def clean_database
    unless Rails.env.development? || Rails.env.test? || Sabha.saas? || DemoMode.enabled?
      abort "⛔ Refusing to clean database in #{Rails.env} without DEMO_MODE=true"
    end

    Notification.delete_all
    Boost.delete_all
    Bookmark.delete_all
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

    Account.first_or_create!(name: "Sabha")
  end
end

namespace :generate do
  namespace :demo do
    desc "Generate MAX demo: 500 users, 2000 messages, all features"
    task max: :environment do
      require "faker"

      if Sabha.saas?
        run_saas_max_demo
      else
        run_single_tenant_max_demo
      end
    end

    def run_saas_max_demo
      puts "🔥 MAXIMUM DEMO MODE (SaaS - 2 workspaces)"
      puts "   500 users, 2000+ messages, all features per workspace"
      puts ""

      workspace_configs = [
        { name: "Acme Corp", admin_email: "admin@acme.com" },
        { name: "Startup Inc", admin_email: "admin@startup.com" }
      ]

      workspaces = create_saas_workspaces(workspace_configs)

      workspaces.each do |workspace|
        puts ""
        puts "=" * 60
        puts "📦 Generating demo for workspace: #{workspace.name} (#{workspace.external_id})"
        puts "=" * 60

        ApplicationRecord.with_tenant(workspace.external_id.to_s) do
          run_single_tenant_max_demo(workspace_name: workspace.name, tenant_id: workspace.external_id.to_s)
        end
      end

      puts ""
      puts "=" * 60
      puts "✅ SaaS MAX demo complete!"
      puts ""
      puts "🔑 Login credentials (password: 'password'):"
      workspaces.each do |ws|
        puts ""
        puts "   #{ws.name} (#{ws.external_id}):"
        puts "     Admin: admin@sabha.co"
        puts "     Mod:   mod@sabha.co"
        puts "     User:  user@sabha.co"
        puts "     URL:   http://localhost:3000/#{ws.external_id}/"
      end
    end

    def run_single_tenant_max_demo(workspace_name: nil, tenant_id: nil)
      puts "🔥 MAXIMUM DEMO MODE" unless workspace_name
      puts "   500 users, 2000+ messages, all features"
      puts ""

      puts "🧹 Cleaning existing data..."
      MaxDemo.clean_database

      puts "🏷️  Creating badges..."
      badges = MaxDemo.create_badges

      puts "👥 Creating 500 users..."
      users = MaxDemo.create_users(badges)

      # In SAAS mode, create GlobalIdentities and WorkspaceMemberships
      create_saas_identities_for_workspace(users, tenant_id) if tenant_id

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

      DemoHelpers.normalize_seed_timestamps!

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

      unless workspace_name
        puts ""
        puts "🔑 Login credentials (password: 'password'):"
        puts "   Admin: admin@sabha.co"
        puts "   Mod:   mod@sabha.co"
        puts "   User:  user@sabha.co"
      end
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

    # Generate a random public IP address, excluding private and reserved ranges
    def random_public_ip
      loop do
        first = rand(1..223)
        # Skip private and reserved ranges
        next if first == 10                           # 10.0.0.0/8
        next if first == 127                          # 127.0.0.0/8
        next if first == 169                          # 169.254.0.0/16 (link-local)

        second = rand(0..255)
        next if first == 172 && (16..31).include?(second)  # 172.16.0.0/12
        next if first == 192 && second == 168              # 192.168.0.0/16

        return "#{first}.#{second}.#{rand(0..255)}.#{rand(1..254)}"
      end
    end

    # Delegate to shared helpers
    def clean_database = DemoHelpers.clean_database
    def mention_html_for(user) = DemoHelpers.mention_html_for(user)
    def body_with_mention(user, text) = DemoHelpers.body_with_mention(user, text)

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
        { name: "Admin User", email_address: "admin@sabha.co", role: 2, bio: "Community administrator", badge_id: badge_ids["Founder"]&.id, current_streak: 45 },
        { name: "Moderator", email_address: "mod@sabha.co", role: 1, bio: "Community moderator", badge_id: badge_ids["Mod"]&.id, current_streak: 12 },
        { name: "Regular User", email_address: "user@sabha.co", role: 0, bio: "Just a regular member", badge_id: nil, current_streak: 3 }
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

      # Query only the users we just created (by email) instead of loading all users
      User.where(email_address: user_records.map { |u| u[:email_address] }).order(:id).to_a
    end

    def create_rooms(users)
      admin = users.first
      rooms = { open: [], closed: [], direct: [] }

      # Open rooms
      open_rooms_data = [
        "General",
        "Introductions",
        "Random",
        "Show & Tell",
        "Help & Support",
        "Announcements",
        "Feedback",
        "Off-Topic"
      ]

      open_rooms_data.each do |name|
        rooms[:open] << Rooms::Open.create!(
          name: name,
          creator: admin,
          auto_join: true
        )
      end
      puts "   Created #{rooms[:open].count} open rooms"

      # Closed rooms with varying membership sizes
      closed_rooms_data = [
        { name: "Founders Circle", size: 25 },
        { name: "Backend Guild", size: 100 },
        { name: "Frontend Crew", size: 90 },
        { name: "Design Team", size: 50 },
        { name: "DevOps", size: 40 },
        { name: "Book Club", size: 75 },
        { name: "Fitness Buddies", size: 60 },
        { name: "Music Lovers", size: 45 },
        { name: "Gaming Squad", size: 100 },
        { name: "Mentorship", size: 30 }
      ]

      closed_rooms_data.each do |data|
        room = Rooms::Closed.create!(
          name: data[:name],
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

      # DMs between special users (1-on-1)
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

      # Group DM with all 3 special users (admin, mod, user)
      if special_users.length >= 3
        Current.user = special_users.first
        begin
          dm = Rooms::Direct.create_for({}, users: special_users)
          rooms[:direct] << dm
          add_special_group_dm_messages(dm, special_users)
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

      # Random DMs between other users (1-on-1)
      50.times do |i|
        participants = other_users.sample(2)
        Current.user = participants.first
        begin
          dm = Rooms::Direct.create_for({}, users: participants)
          rooms[:direct] << dm
        rescue ActiveRecord::RecordInvalid
          nil
        end
        print "." if (i % 25).zero?
      end

      # Group DMs (3-5 participants)
      print " groups: "
      group_dm_count = 0

      # Group DMs including special users
      special_users.each do |special|
        group_members = [ special ] + other_users.sample(rand(2..4))
        Current.user = special
        begin
          dm = Rooms::Direct.create_for({}, users: group_members)
          rooms[:direct] << dm
          add_dm_messages(dm, group_members)
          group_dm_count += 1
        rescue ActiveRecord::RecordInvalid
          nil
        end
      end

      # Additional random group DMs
      12.times do
        participants = other_users.sample(rand(3..5))
        Current.user = participants.first
        begin
          dm = Rooms::Direct.create_for({}, users: participants)
          rooms[:direct] << dm
          add_dm_messages(dm, participants)
          group_dm_count += 1
        rescue ActiveRecord::RecordInvalid
          nil
        end
      end

      Current.user = nil
      puts "done! (#{rooms[:direct].count} DMs, #{group_dm_count} group)"

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

    def add_special_group_dm_messages(dm, participants)
      base_time = rand(3..7).days.ago
      admin, mod, regular = participants

      # A realistic conversation between admin, mod, and regular user
      conversation = [
        { user: admin, body: "Hey team! Quick sync about community updates 👋" },
        { user: mod, body: "Hey! Perfect timing, I had some things to discuss" },
        { user: regular, body: "Hi! What's up?" },
        { user: admin, body: "Just wanted to check in on how things are going" },
        { user: mod, body: "All good on my end. Handled a few reports this week" },
        { user: regular, body: "Same here, loving the community so far!" },
        { user: admin, body: "Great to hear! Let me know if you need anything" },
        { user: mod, body: "Will do 👍" },
        { user: regular, body: "Thanks!" }
      ]

      conversation.each_with_index do |msg, i|
        time_offset = (i * rand(2..10)).minutes

        begin
          Message.create!(
            room: dm,
            creator: msg[:user],
            body: msg[:body],
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

          # Add proper ActionText mentions occasionally
          if rand < 0.1 && room_users.length > 1
            mentioned = (room_users - [ user ]).sample
            body = body_with_mention(mentioned, body)
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

      # Create specific mentions for special users (admin, mod, user@sabha.co)
      special_users = users.select { |u| u.email_address.include?("sabha.co") }
      if special_users.any?
        print " mentions for special users: "
        open_rooms = rooms[:open]

        special_users.each do |special|
          # Create 3-5 messages mentioning each special user in different rooms
          rand(3..5).times do
            room = open_rooms.sample
            room_users = room.users.to_a - [ special ]
            next if room_users.empty?

            sender = room_users.sample
            body = body_with_mention(special, CHAT_MESSAGES.sample)

            begin
              Message.create!(
                room: room,
                creator: sender,
                body: body,
                created_at: rand(1..14).days.ago,
                client_message_id: SecureRandom.uuid
              )
              message_count += 1
            rescue ActiveRecord::RecordInvalid
              nil
            end
          end
          print "."
        end
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
      special_users = users.select { |u| u.email_address.include?("sabha.co") }

      # First, create threads specifically for special users (they'll be thread creators)
      print "   Creating threads for special users: "
      thread_count = 0

      special_users.each do |special|
        # Find messages in rooms the special user is a member of (not their own messages)
        special_room_ids = special.room_ids
        parent_messages = Message.includes(room: :users)
                                  .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                                  .where(room_id: special_room_ids)
                                  .where.not(creator_id: special.id)
                                  .where("messages.created_at < ?", 3.days.ago)
                                  .order("RANDOM()")
                                  .limit(2)

        parent_messages.each do |parent|
          room_users = parent.room.users.to_a
          Current.user = special  # Special user creates the thread

          begin
            thread = Rooms::Thread.create_for(
              { parent_message_id: parent.id },
              users: room_users
            )

            base_time = parent.created_at + rand(30..180).minutes

            # First message from special user
            Message.create!(
              room: thread,
              creator: special,
              body: THREAD_STARTERS.sample,
              created_at: base_time,
              client_message_id: SecureRandom.uuid
            )

            # Replies from others
            rand(3..6).times do |i|
              user = (room_users - [ special ]).sample || room_users.sample
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
      end

      # Also create threads on messages BY special users (they'll be parent message creators)
      special_messages = Message.includes(room: :users)
                                 .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                                 .where(creator_id: special_users.map(&:id))
                                 .where("messages.created_at < ?", 3.days.ago)
                                 .order("RANDOM()")
                                 .limit(special_users.length * 2)

      special_messages.each do |parent|
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

          Message.create!(
            room: thread,
            creator: creator,
            body: THREAD_STARTERS.sample,
            created_at: base_time,
            client_message_id: SecureRandom.uuid
          )

          rand(3..6).times do |i|
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

      # Now create random threads for other users
      print " random: "
      threadable = Message.includes(room: :users)
                          .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                          .where.not(id: Rooms::Thread.select(:parent_message_id))  # Exclude messages that already have threads
                          .where("messages.created_at < ?", 3.days.ago)
                          .order("RANDOM()")
                          .limit(20)

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

          Message.create!(
            room: thread,
            creator: creator,
            body: THREAD_STARTERS.sample,
            created_at: base_time,
            client_message_id: SecureRandom.uuid
          )

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
      messages = Message.includes(room: :users)
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

      # Special users always get bookmarks (3-5 each)
      special_users = users.select { |u| u.email_address.include?("sabha.co") }
      special_users.each do |user|
        message_ids = Message.where(room_id: user.room_ids, active: true)
                             .where.not(creator_id: user.id)
                             .order("RANDOM()")
                             .limit(rand(3..5))
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

      # ~20% of other users bookmark things
      other_users = users.reject { |u| u.email_address.include?("sabha.co") }
      bookmarking_users = other_users.sample(other_users.count / 5)

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
      puts "   Created #{bookmark_records.count} bookmarks (#{special_users.count} special users)"
    end

    def create_blocks(users)
      now = Time.current
      regular_users = users.reject { |u| u.email_address.include?("sabha.co") }
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
      bannable = users.reject { |u| u.email_address.include?("sabha.co") }
      to_ban = bannable.sample(15)
      now = Time.current

      # Bulk create sessions with random IPs
      session_records = []
      to_ban.each do |user|
        rand(1..2).times do
          created = now - rand(1..30).days
          session_records << {
            user_id: user.id,
            ip_address: random_public_ip,
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
        u.email_address.include?("sabha.co") || u.banned?
      end
      to_deactivate = deactivatable.sample(25)

      to_deactivate.each(&:deactivate)
      puts "   Deactivated #{to_deactivate.count} users"
    end

    def set_streaks
      # Set streaks at the end to avoid being overwritten by message callbacks
      # Special users keep their fixed streaks
      User.where(email_address: "admin@sabha.co").update_all(current_streak: 45)
      User.where(email_address: "mod@sabha.co").update_all(current_streak: 12)
      User.where(email_address: "user@sabha.co").update_all(current_streak: 3)

      # Random streaks for other users: 60% zero, 20% short, 15% medium, 5% long
      other_users = User.where.not(email_address: %w[admin@sabha.co mod@sabha.co user@sabha.co])
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

    if Sabha.saas?
      run_saas_demo
    else
      run_single_tenant_demo
    end
  end

  def run_saas_demo
    puts "📦 DEMO MODE (SaaS - 2 workspaces)"
    puts ""

    workspace_configs = [
      { name: "Acme Corp", admin_email: "admin@acme.com" },
      { name: "Startup Inc", admin_email: "admin@startup.com" }
    ]

    workspaces = create_saas_workspaces(workspace_configs)

    # Use simple password locally, random password in production
    demo_password = Rails.env.local? ? "password" : SecureRandom.alphanumeric(12)

    workspaces.each do |workspace|
      puts ""
      puts "=" * 60
      puts "📦 Generating demo for workspace: #{workspace.name} (#{workspace.external_id})"
      puts "=" * 60

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        run_single_tenant_demo(demo_password: demo_password, workspace_name: workspace.name, tenant_id: workspace.external_id.to_s)
      end
    end

    puts ""
    puts "=" * 60
    puts "✅ SaaS demo complete!"
    puts ""
    puts "🔑 Login credentials (password: '#{demo_password}'):"
    workspaces.each do |ws|
      puts ""
      puts "   #{ws.name} (#{ws.external_id}):"
      puts "     Admin: admin@sabha.co"
      puts "     Mod:   mod@sabha.co"
      puts "     User:  user@sabha.co"
      puts "     URL:   http://localhost:3000/#{ws.external_id}/"
    end
  end

  def run_single_tenant_demo(demo_password: nil, workspace_name: nil, tenant_id: nil)
    # Use simple password locally, random password in production
    demo_password ||= Rails.env.local? ? "password" : SecureRandom.alphanumeric(12)

    puts "🧹 Cleaning existing data..."
    clean_database

    puts "👥 Creating demo users..."
    users = create_users(demo_password)

    # In SAAS mode, create GlobalIdentities and WorkspaceMemberships
    create_saas_identities_for_workspace(users, tenant_id) if tenant_id

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

    DemoHelpers.normalize_seed_timestamps!

    puts "✅ Demo environment ready!"
    puts ""
    puts "📊 Summary:"
    puts "   Users: #{User.count}"
    puts "   Rooms: #{Room.where(type: %w[Rooms::Open Rooms::Closed]).count} (+ #{Rooms::Direct.count} DMs, #{Rooms::Thread.count} threads)"
    puts "   Messages: #{Message.count}"
    puts "   Boosts: #{Boost.count}"
    puts "   Bookmarks: #{Bookmark.count}"

    unless workspace_name
      puts ""
      puts "🔑 Login credentials (password: '#{demo_password}'):"
      puts "   Admin: admin@sabha.co"
      puts "   Mod:   mod@sabha.co"
      puts "   User:  user@sabha.co"
    end
  end

  def create_saas_workspaces(configs)
    puts "🏢 Creating #{configs.length} workspaces..."

    creator_emails = configs.map { |c| c[:admin_email].downcase }

    # Clean existing workspaces and their tenant databases
    Workspace.find_each do |workspace|
      puts "   Destroying existing workspace #{workspace.external_id}..."
      ApplicationRecord.destroy_tenant(workspace.external_id.to_s) rescue nil
      workspace.destroy!
    end

    # Clean up all SAAS data except workspace creators
    # Order matters: sessions/codes first, then memberships, then identities
    puts "   Cleaning up SAAS identities..."
    GlobalSession.delete_all
    AuthCode.delete_all
    WorkspaceMembership.delete_all
    GlobalIdentity.where.not(email_address: creator_emails).delete_all

    workspaces = []
    configs.each do |config|
      creator = GlobalIdentity.find_or_create_by!(email_address: config[:admin_email].downcase)
      creator.verify! unless creator.verified?

      workspace = Workspace.create_with_database!(
        name: config[:name],
        creator: creator
      )
      workspaces << workspace
      puts "   Created: #{workspace.name} (ID: #{workspace.external_id})"
    end

    workspaces
  end

  # Create GlobalIdentity and WorkspaceMembership for a user in SAAS mode
  # Returns the WorkspaceMembership record
  def create_saas_identity_for_user(user, tenant_id)
    identity = GlobalIdentity.find_or_create_by!(email_address: user.email_address.downcase)
    identity.verify! unless identity.verified?

    membership = identity.workspace_memberships.find_or_create_by!(tenant: tenant_id)
    membership.cache_user_id!(user.id)

    # Link User to WorkspaceMembership
    user.update_column(:workspace_membership_id, membership.id)

    membership
  end

  # Batch create SAAS identities for all users in a workspace
  def create_saas_identities_for_workspace(users, tenant_id)
    return unless Sabha.saas?

    puts "   Creating GlobalIdentities and WorkspaceMemberships..."
    users.each do |user|
      create_saas_identity_for_user(user, tenant_id)
    end
  end

  desc "Generate messages in a specific room (default: General)"
  task lines: :environment do
    room = Room.find_by(name: "General")
    users = User.all

    1.upto(500) do |i|
      room.messages.create! \
        body: "Message #{i}",
        creator: users.sample,
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

  # Delegate to shared helpers
  def clean_database = DemoHelpers.clean_database
  def mention_html_for(user) = DemoHelpers.mention_html_for(user)
  def body_with_mention(user, text) = DemoHelpers.body_with_mention(user, text)

  def create_users(password)
    # Admin user
    admin = User.create!(
      name: "Admin User",
      email_address: "admin@sabha.co",
      password: password,
      password_confirmation: password,
      role: "administrator",
      bio: "Community administrator",
      verified_at: Time.current
    )

    # Moderator user
    mod = User.create!(
      name: "Moderator",
      email_address: "mod@sabha.co",
      password: password,
      password_confirmation: password,
      role: "moderator",
      bio: "Community moderator",
      verified_at: Time.current
    )

    # Regular user with @sabha.co email for easy testing
    regular = User.create!(
      name: "Regular User",
      email_address: "user@sabha.co",
      password: password,
      password_confirmation: password,
      role: "member",
      bio: "Just a regular member",
      verified_at: Time.current
    )

    # Additional users with varied profiles
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

    users = [ admin, mod, regular ]

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
      { name: "General", key: "general" },
      { name: "Introductions", key: "introductions" },
      { name: "Random", key: "random" },
      { name: "Show & Tell", key: "show-and-tell" },
      { name: "Help & Support", key: "help" }
    ]

    open_rooms.each do |room_data|
      rooms[room_data[:key]] = Rooms::Open.create!(
        name: room_data[:name],
        creator: admin,
        auto_join: true
      )
    end

    # Closed rooms (invite only)
    closed_rooms = [
      { name: "Founders Circle", key: "founders", members: users.sample(6) },
      { name: "Backend Guild", key: "backend", members: users.sample(5) },
      { name: "Design Crew", key: "design", members: users.sample(4) },
      { name: "Book Club", key: "books", members: users.sample(7) }
    ]

    closed_rooms.each do |room_data|
      room = Rooms::Closed.create!(
        name: room_data[:name],
        creator: admin
      )
      room.memberships.grant_to([ admin ] + room_data[:members])
      rooms[room_data[:key]] = room
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
    rooms.each do |key, room|
      next if room.direct? # DMs handled separately

      room_users = room.users.to_a
      message_count = case key
      when "general" then rand(80..120)
      when "introductions" then rand(15..25)
      when "random" then rand(40..60)
      when "show-and-tell" then rand(20..35)
      when "help" then rand(30..50)
      else rand(20..40)
      end

      templates = case key
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

        # Occasionally add proper ActionText mentions
        if rand < 0.15 && room_users.length > 1
          mentioned_user = (room_users - [ user ]).sample
          body = body_with_mention(mentioned_user, body)
        end

        # Occasionally add replies/reactions
        body = "#{%w[+1 👍 This! Agree! 💯 Nice!].sample}" if rand < 0.08

        create_message_safely(room, user, body, base_time + time_offset)
      end

      print "."
    end

    # Create specific mentions for the admin user
    admin = users.find { |u| u.email_address == "admin@sabha.co" }
    if admin
      print " admin mentions: "
      open_room_keys = %w[general random help show-and-tell]
      open_room_keys.each do |key|
        room = rooms[key]
        next unless room

        room_users = room.users.to_a - [ admin ]
        next if room_users.empty?

        # Create 2-3 messages mentioning admin in each room
        rand(2..3).times do
          sender = room_users.sample
          body = body_with_mention(admin, [ "what do you think?", "any thoughts?", "need your input on this", "can you help?" ].sample)
          create_message_safely(room, sender, body, rand(1..14).days.ago)
        end
        print "."
      end
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

  # Wrapper for positional args (delegates to shared helper)
  def create_message_safely(room, user, body, created_at)
    DemoHelpers.create_message_safely(room: room, creator: user, body: body, created_at: created_at)
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

    # First, create threads where admin is the thread creator (so admin can see them)
    admin = users.find { |u| u.email_address == "admin@sabha.co" }
    if admin
      print " admin threads: "
      admin_room_ids = admin.room_ids
      admin_threadable = Message.includes(room: :users)
                                 .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                                 .where(room_id: admin_room_ids)
                                 .where.not(creator_id: admin.id)
                                 .where("messages.created_at < ?", 2.days.ago)
                                 .order("RANDOM()")
                                 .limit(3)

      admin_threadable.each do |parent_message|
        room_users = parent_message.room.users.to_a
        Current.user = admin  # Admin creates the thread

        thread = Rooms::Thread.create_for(
          { parent_message_id: parent_message.id },
          users: room_users
        )

        base_time = parent_message.created_at + rand(30..180).minutes
        create_message_safely(thread, admin, thread_starters.sample.call, base_time)

        rand(3..6).times do |i|
          user = (room_users - [ admin ]).sample || room_users.sample
          time_offset = (i + 1) * rand(5..30).minutes
          create_message_safely(thread, user, thread_replies.sample.call, base_time + time_offset)
        end

        print "."
      end

      # Also create threads on messages BY admin (admin is parent message creator)
      admin_messages = Message.includes(room: :users)
                               .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                               .where(creator_id: admin.id)
                               .where("messages.created_at < ?", 2.days.ago)
                               .order("RANDOM()")
                               .limit(2)

      admin_messages.each do |parent_message|
        room_users = parent_message.room.users.to_a
        next if room_users.length < 2

        thread_creator = (room_users - [ admin ]).sample || room_users.sample
        Current.user = thread_creator

        thread = Rooms::Thread.create_for(
          { parent_message_id: parent_message.id },
          users: room_users
        )

        base_time = parent_message.created_at + rand(30..180).minutes
        create_message_safely(thread, thread_creator, thread_starters.sample.call, base_time)

        rand(3..6).times do |i|
          user = room_users.sample
          time_offset = (i + 1) * rand(5..30).minutes
          create_message_safely(thread, user, thread_replies.sample.call, base_time + time_offset)
        end

        print "."
      end
    end

    # Pick some more random messages from non-DM rooms to start threads on
    print " random: "
    threadable_messages = Message.includes(room: :users)
                                  .where.not(rooms: { type: [ "Rooms::Direct", "Rooms::Thread" ] })
                                  .where.not(id: Rooms::Thread.select(:parent_message_id))
                                  .where("messages.created_at < ?", 2.days.ago)
                                  .order("RANDOM()")
                                  .limit(5)

    threadable_messages.each do |parent_message|
      room_users = parent_message.room.users.to_a
      next if room_users.length < 2

      thread_creator = (room_users - [ parent_message.creator ]).sample || room_users.sample
      Current.user = thread_creator

      thread = Rooms::Thread.create_for(
        { parent_message_id: parent_message.id },
        users: room_users
      )

      base_time = parent_message.created_at + rand(30..180).minutes
      create_message_safely(thread, thread_creator, thread_starters.sample.call, base_time)

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
    now = Time.current
    boost_records = []

    messages = Message.includes(room: :users)
                      .where.not(rooms: { type: "Rooms::Direct" })
                      .order("RANDOM()")
                      .limit(50)

    messages.each do |message|
      boosters = (message.room.users.to_a - [ message.creator ]).sample(rand(1..4))
      boosters.each do |booster|
        boost_records << {
          message_id: message.id,
          booster_id: booster.id,
          content: boost_emojis.sample,
          created_at: message.created_at + rand(1..60).minutes,
          updated_at: now
        }
      end
    end

    Boost.insert_all(boost_records) if boost_records.any?
  end

  def create_bookmarks(users)
    now = Time.current
    bookmark_records = []

    users.each do |user|
      # Each user bookmarks a few random messages from rooms they're in
      message_ids = Message.where(room_id: user.room_ids)
                           .order("RANDOM()")
                           .limit(rand(3..8))
                           .pluck(:id)

      message_ids.each do |message_id|
        bookmark_records << {
          user_id: user.id,
          message_id: message_id,
          created_at: now - rand(1..120).minutes,
          updated_at: now
        }
      end
    end

    Bookmark.insert_all(bookmark_records) if bookmark_records.any?
  end
end
