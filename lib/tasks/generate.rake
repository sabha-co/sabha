# rails generate:demo

namespace :generate do
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
