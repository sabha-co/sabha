# rails generate:demo:workspace[name,email]
#
# Creates a single demo workspace in SaaS mode with 100 users, 500 messages,
# threads, boosts, bookmarks. Production-safe: no Faker, doesn't touch
# existing workspaces.

module WorkspaceDemo
  extend self

  FIRST_NAMES = %w[
    James Mary Robert Patricia John Jennifer Michael Linda David Elizabeth
    William Barbara Richard Susan Joseph Jessica Thomas Sarah Charles Karen
    Christopher Lisa Daniel Nancy Matthew Betty Mark Sandra Donald Ashley
    Steven Emily Andrew Kimberly Paul Donna Joshua Michelle Kenneth Carol
    Kevin Amanda Brian Dorothy George Melissa Edward Rebecca Timothy Deborah
    Ronald Stephanie Jason Sharon Jeffrey Laura Ryan Cynthia Jacob Kathleen
    Gary Amy Nicholas Angela Eric Shirley Stephen Anna Larry Brenda
    Jonathan Ruth Scott Pamela Raymond Samantha Frank Andrea Patrick Virginia
    Benjamin Katherine Peter Debra Gregory Janet Samuel Alice Alexander Jean
    Jack Abigail Dennis Marie Jerry Denise Tyler Julie Aaron Martha
    Adam Frances Nathan Janice Carl Gloria Henry Kathryn Philip Teresa
  ].freeze

  LAST_NAMES = %w[
    Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez
    Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin
    Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson
    Walker Young Allen King Wright Scott Torres Nguyen Hill Flores
    Green Adams Nelson Baker Hall Rivera Campbell Mitchell Carter Roberts
    Gomez Phillips Evans Turner Diaz Parker Cruz Edwards Collins Reyes
    Stewart Morris Morales Murphy Cook Rogers Gutierrez Ortiz Morgan Cooper
    Peterson Bailey Reed Kelly Howard Ramos Kim Cox Ward Richardson
    Watson Brooks Chavez Wood James Bennett Gray Mendoza Ruiz Hughes
    Price Alvarez Castillo Sanders Patel Myers Long Ross Foster Jimenez
  ].freeze

  BIOS = [
    "Product designer & coffee enthusiast",
    "Full-stack developer. Building cool stuff.",
    "UX researcher | Always curious",
    "Engineering lead",
    "Indie hacker. Shipped 3 products this year",
    "Backend engineer. Rust & Go.",
    "Mobile dev | SwiftUI enthusiast",
    "DevOps & Cloud | AWS certified",
    "Technical writer & documentation nerd",
    "Startup founder. Angel investor.",
    "Junior dev learning in public",
    "15y in tech. Mentoring is my passion.",
    "Data scientist | ML/AI",
    "Security engineer. Breaking things (ethically).",
    "Product manager turned founder",
    "Open source contributor",
    "Building the future of work",
    "React Native developer",
    "Platform engineer at a startup",
    "Freelance consultant | Ruby & Rails",
    "Systems programmer | Performance nerd",
    "Designer who codes",
    "Community builder",
    "Working on something new",
    "Making the web a better place",
    "Lifelong learner",
    "Building tools for developers",
    "AI/ML researcher",
    "Blockchain skeptic, web enthusiast",
    "Just here to help"
  ].freeze

  CHAT_MESSAGES = [
    "Just shipped a new feature!",
    "Anyone else working late tonight?",
    "Great discussion in the meeting today",
    "Has anyone tried the new update?",
    "Quick question about the API...",
    "Thanks for the help earlier!",
    "This is exactly what I needed",
    "Working on something cool, will share soon",
    "Love this community!",
    "Monday motivation",
    "Finally fixed that bug",
    "Who's up for a code review?",
    "Just learned something new today",
    "This thread is gold",
    "Bookmarking this for later",
    "+1",
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

  BOOST_EMOJIS = %w[👍 ❤️ 🔥 😂 🎉 👏 💯 🙌 ✨ 🚀].freeze

  THREAD_STARTERS = [
    "Let's discuss this further!",
    "Expanding on this point...",
    "Great question! Here's more context:",
    "I have thoughts on this",
    "Jumping in with some details"
  ].freeze

  THREAD_REPLIES = [
    "Good point!",
    "I agree completely",
    "Interesting perspective",
    "To add to this...",
    "+1",
    "This! Exactly!",
    "Makes sense",
    "Thanks for sharing"
  ].freeze

  # --- Users ---

  def create_users(badges, admin_email:)
    password_digest = BCrypt::Password.create("password")
    now = Time.current
    badge_ids = badges.index_by(&:name)

    user_records = [
      { name: "Admin User", email_address: admin_email, password_digest: password_digest,
        role: 2, bio: "Community administrator", twitter_url: nil, linkedin_url: nil,
        badge_id: badge_ids["Founder"]&.id, current_streak: 45,
        verified_at: now, created_at: now, updated_at: now }
    ]

    used_emails = Set.new([ admin_email ])
    name_pairs = FIRST_NAMES.product(LAST_NAMES).shuffle

    99.times do |i|
      first, last = name_pairs[i]
      email = "#{first.downcase}.#{last.downcase}@example.com"
      email = "#{first.downcase}.#{last.downcase}.#{i}@example.com" if used_emails.include?(email)
      used_emails << email

      user_records << {
        name: "#{first} #{last}", email_address: email, password_digest: password_digest,
        role: rand < 0.03 ? 1 : 0,
        bio: rand < 0.7 ? BIOS.sample : nil,
        twitter_url: nil, linkedin_url: nil,
        badge_id: rand < 0.1 ? badges.sample.id : nil,
        current_streak: 0,
        verified_at: now, created_at: now - rand(1..90).days, updated_at: now
      }
    end

    User.insert_all(user_records)
    User.where(email_address: user_records.map { |u| u[:email_address] }).order(:id).to_a
  end

  def create_saas_identities(users, tenant_id)
    users.each do |user|
      identity = GlobalIdentity.find_or_create_by!(email_address: user.email_address.downcase)
      identity.update!(name: user.name) if identity.name.blank? && user.name.present?
      identity.verify! unless identity.verified?
      membership = identity.workspace_memberships.find_or_create_by!(tenant: tenant_id)
      membership.cache_user_id!(user.id)
      user.update_column(:workspace_membership_id, membership.id)
    end
  end

  # --- Rooms ---

  def create_rooms(users)
    admin = users.first
    rooms = { open: [], closed: [], direct: [] }

    # 6 open rooms
    %w[General Introductions Random Announcements Feedback Off-Topic].each do |name|
      rooms[:open] << Rooms::Open.create!(name: name, creator: admin, auto_join: true)
    end

    # 4 closed rooms
    [ { name: "Founders Circle", size: 15 },
      { name: "Backend Guild", size: 30 },
      { name: "Design Team", size: 20 },
      { name: "Book Club", size: 25 } ].each do |data|
      room = Rooms::Closed.create!(name: data[:name], creator: admin)
      room.memberships.grant_to(([ admin ] + users.sample(data[:size])).uniq)
      rooms[:closed] << room
    end

    # 20 DMs
    other_users = users[1..]

    # 3 group DMs with admin
    3.times do
      group = [ admin ] + other_users.sample(rand(2..4))
      Current.user = admin
      dm = Rooms::Direct.create_for({}, users: group)
      rooms[:direct] << dm
    rescue ActiveRecord::RecordInvalid
      nil
    end

    # 5 1-on-1 DMs with admin
    other_users.sample(5).each do |other|
      Current.user = admin
      dm = Rooms::Direct.create_for({}, users: [ admin, other ])
      rooms[:direct] << dm
    rescue ActiveRecord::RecordInvalid
      nil
    end

    # 12 random DMs (mix of 1-on-1 and group)
    12.times do
      participants = other_users.sample(rand < 0.3 ? rand(3..4) : 2)
      Current.user = participants.first
      dm = Rooms::Direct.create_for({}, users: participants)
      rooms[:direct] << dm
    rescue ActiveRecord::RecordInvalid
      nil
    end

    Current.user = nil
    rooms
  end

  # --- Messages ---

  def create_messages(rooms, users)
    admin = users.first
    message_count = 0

    # ~30 messages per open/closed room = ~300
    (rooms[:open] + rooms[:closed]).each do |room|
      room_users = room.users.to_a
      next if room_users.empty?

      base_time = rand(14..30).days.ago
      30.times do |i|
        user = room_users.sample
        body = CHAT_MESSAGES.sample

        if rand < 0.1 && room_users.length > 1
          mentioned = (room_users - [ user ]).sample
          body = DemoHelpers.body_with_mention(mentioned, body)
        end

        DemoHelpers.create_message_safely(room: room, creator: user, body: body, created_at: base_time + (i * rand(5..30)).minutes)
        message_count += 1
      end
    end

    # 5 explicit mentions of admin in different rooms
    rooms[:open].sample(3).each do |room|
      room_users = room.users.to_a - [ admin ]
      next if room_users.empty?

      sender = room_users.sample
      body = DemoHelpers.body_with_mention(admin, CHAT_MESSAGES.sample)
      DemoHelpers.create_message_safely(room: room, creator: sender, body: body, created_at: rand(1..7).days.ago)
      message_count += 1
    end

    # ~10 messages per DM = ~200
    dm_bodies = [ "Hey!", "What's up?", "Sounds good", "Thanks!", "Perfect", "Got it", "Let me know" ]
    rooms[:direct].each do |dm|
      dm_users = dm.users.to_a
      next if dm_users.length < 2

      base_time = rand(7..21).days.ago
      rand(8..12).times do |i|
        DemoHelpers.create_message_safely(room: dm, creator: dm_users.sample, body: dm_bodies.sample, created_at: base_time + (i * rand(5..60)).minutes)
        message_count += 1
      end
    end

    message_count
  end

  # --- Threads ---

  def create_threads(rooms, users)
    admin = users.first
    thread_count = 0

    # 2 threads started by admin
    admin_room_ids = admin.room_ids
    parent_messages = Message.includes(room: :users)
                             .where.not(rooms: { type: %w[Rooms::Direct Rooms::Thread] })
                             .where(room_id: admin_room_ids)
                             .where.not(creator_id: admin.id)
                             .where("messages.created_at < ?", 3.days.ago)
                             .order("RANDOM()").limit(2)

    parent_messages.each do |parent|
      room_users = parent.room.users.to_a
      Current.user = admin
      thread = Rooms::Thread.create_for({ parent_message_id: parent.id }, users: room_users)
      base_time = parent.created_at + rand(30..180).minutes

      Message.create!(room: thread, creator: admin, body: THREAD_STARTERS.sample, created_at: base_time, client_message_id: SecureRandom.uuid)
      rand(3..5).times do |i|
        Message.create!(room: thread, creator: (room_users - [ admin ]).sample || room_users.sample, body: THREAD_REPLIES.sample, created_at: base_time + ((i + 1) * rand(5..30)).minutes, client_message_id: SecureRandom.uuid)
      end
      thread_count += 1
    rescue ActiveRecord::RecordInvalid
      nil
    end

    # 5 random threads
    threadable = Message.includes(room: :users)
                         .where.not(rooms: { type: %w[Rooms::Direct Rooms::Thread] })
                         .where.not(id: Rooms::Thread.select(:parent_message_id))
                         .where("messages.created_at < ?", 3.days.ago)
                         .order("RANDOM()").limit(5)

    threadable.each do |parent|
      room_users = parent.room.users.to_a
      next if room_users.length < 2

      creator = (room_users - [ parent.creator ]).sample || room_users.sample
      Current.user = creator
      thread = Rooms::Thread.create_for({ parent_message_id: parent.id }, users: room_users)
      base_time = parent.created_at + rand(30..180).minutes

      Message.create!(room: thread, creator: creator, body: THREAD_STARTERS.sample, created_at: base_time, client_message_id: SecureRandom.uuid)
      rand(3..6).times do |i|
        Message.create!(room: thread, creator: room_users.sample, body: THREAD_REPLIES.sample, created_at: base_time + ((i + 1) * rand(5..30)).minutes, client_message_id: SecureRandom.uuid)
      end
      thread_count += 1
    rescue ActiveRecord::RecordInvalid
      nil
    end

    Current.user = nil
    thread_count
  end

  # --- Boosts ---

  def create_boosts
    messages = Message.includes(room: :users)
                      .where.not(rooms: { type: "Rooms::Direct" })
                      .where(active: true)
                      .order("RANDOM()").limit(60)

    now = Time.current
    records = []
    messages.each do |msg|
      boosters = (msg.room.user_ids - [ msg.creator_id ]).sample(rand(1..3))
      boosters.each do |booster_id|
        records << { message_id: msg.id, booster_id: booster_id, content: BOOST_EMOJIS.sample,
                     created_at: msg.created_at + rand(1..120).minutes, updated_at: now }
      end
    end

    Boost.insert_all(records) if records.any?
    records.count
  end

  # --- Bookmarks ---

  def create_bookmarks(users)
    admin = users.first
    now = Time.current
    records = []

    # Admin gets 5 bookmarks
    Message.where(room_id: admin.room_ids, active: true).where.not(creator_id: admin.id)
           .order("RANDOM()").limit(5).pluck(:id).each do |mid|
      records << { user_id: admin.id, message_id: mid, created_at: now - rand(1..180).minutes, updated_at: now }
    end

    # ~20% of other users get 1-3 bookmarks
    users[1..].sample(users.count / 5).each do |user|
      Message.where(room_id: user.room_ids, active: true).order("RANDOM()").limit(rand(1..3)).pluck(:id).each do |mid|
        records << { user_id: user.id, message_id: mid, created_at: now - rand(1..180).minutes, updated_at: now }
      end
    end

    Bookmark.insert_all(records) if records.any?
    records.count
  end
end

namespace :generate do
  namespace :demo do
    desc "Create a demo workspace with 100 users, 500 messages, threads, boosts, bookmarks (production-safe, no Faker)"
    task :workspace, [ :name, :email ] => :environment do |_, args|
      abort "SaaS mode required. Enable with: bin/rails saas:enable" unless Sabha.saas?

      name = args[:name].presence || "Demo Workspace"
      email = args[:email].presence || "demo@sabha.co"

      puts "Creating workspace: #{name} (admin: #{email})"

      identity = GlobalIdentity.find_or_create_by!(email_address: email.downcase)
      identity.verify! unless identity.verified?

      workspace = Workspace.create_with_database!(name: name, creator: identity)
      tenant_id = workspace.external_id.to_s
      puts "   Workspace #{workspace.external_id}"

      # Eager load after create_with_database! (which may run migrations and trigger Zeitwerk reload)
      Rails.application.eager_load!

      ApplicationRecord.with_tenant(tenant_id) do
        DemoHelpers.clean_database

        puts "   Badges..."
        badges = MaxDemo.create_badges

        puts "   100 users..."
        users = WorkspaceDemo.create_users(badges, admin_email: email)
        WorkspaceDemo.create_saas_identities(users, tenant_id)

        puts "   10 rooms + 20 DMs..."
        rooms = WorkspaceDemo.create_rooms(users)

        puts "   Messages..."
        msg_count = WorkspaceDemo.create_messages(rooms, users)

        puts "   Threads..."
        thread_count = WorkspaceDemo.create_threads(rooms, users)

        puts "   Boosts..."
        boost_count = WorkspaceDemo.create_boosts

        puts "   Bookmarks..."
        bookmark_count = WorkspaceDemo.create_bookmarks(users)

        puts ""
        puts "Done! /#{workspace.external_id}/"
        puts "   Users: #{User.count} | Rooms: #{Room.where(type: %w[Rooms::Open Rooms::Closed]).count} | DMs: #{Rooms::Direct.count} | Threads: #{Rooms::Thread.count}"
        puts "   Messages: #{Message.count} | Boosts: #{Boost.count} | Bookmarks: #{Bookmark.count}"
        puts "   Login: #{email} / password"
      end
    end
  end
end
