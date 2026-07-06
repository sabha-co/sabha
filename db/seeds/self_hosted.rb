# Self-hosted development seed data
#
# Creates a small community with 3 users, 4 rooms, messages, threads, boosts, and bookmarks.
# Sign in as ashwin@sabha.co / password

Account.find_or_create_by!(singleton_guard: 0) do |account|
  account.name = "Sabha"
end

# Users
ashwin = find_or_create_user "Ashwin M", "ashwin@sabha.co", role: :administrator
jason  = find_or_create_user "Jason Fried", "jason@sabha.co"
david  = find_or_create_user "David Heinemeier Hansson", "david@sabha.co"

everyone = [ ashwin, jason, david ]

Current.user = ashwin

# Rooms
general = Rooms::Open.find_or_create_by!(name: "General") do |room|
  room.slug = "general"
  room.creator = ashwin
  room.auto_join = true
end
general.memberships.grant_to(everyone)

random = Rooms::Open.find_or_create_by!(name: "Random") do |room|
  room.creator = jason
end
random.memberships.grant_to(everyone)

engineering = Rooms::Closed.find_or_create_by!(name: "Engineering") do |room|
  room.creator = ashwin
end
engineering.memberships.grant_to([ ashwin, jason ])

dm = Rooms::Direct.find_or_create_for([ ashwin, david ])

# Messages — spread over last 7 days
times = spread_times(20)

m1  = post_message general, ashwin, "Welcome to Sabha! This is the general channel for everyone.", at: times[0]
m2  = post_message general, jason,  "Hey everyone, glad to be here.", at: times[1]
m3  = post_message general, david,  "Thanks for setting this up Ashwin!", at: times[2]
m4  = post_message general, ashwin, "Feel free to create new rooms for specific topics.", at: times[3]
m5  = post_message general, jason,  "Has anyone tried the thread feature yet?", at: times[4]

m6  = post_message random, david,  "Random thought: we should do a team lunch soon.", at: times[5]
m7  = post_message random, jason,  "I'm in! How about Friday?", at: times[6]
m8  = post_message random, ashwin, "Friday works for me too.", at: times[7]
m9  = post_message random, david,  "/play tada", at: times[8]

m10 = post_message engineering, ashwin, "Let's use this room for technical discussions.", at: times[9]
m11 = post_message engineering, jason,  "Sounds good. I've been looking at the new Rails features.", at: times[10]
m12 = post_message engineering, ashwin, "The Solid Queue integration is really nice.", at: times[11]
m13 = post_message engineering, jason,  "Agreed. No more Redis dependency for background jobs.", at: times[12]

m14 = post_message dm, ashwin, "Hey David, do you have a minute?", at: times[13]
m15 = post_message dm, david,  "Sure, what's up?", at: times[14]
m16 = post_message dm, ashwin, "Just wanted to check in on the design mockups.", at: times[15]
m17 = post_message dm, david,  "Almost done! I'll share them tomorrow.", at: times[16]

m18 = post_message general, david,  "Quick update: the new designs are looking great.", at: times[17]
m19 = post_message general, ashwin, "Can't wait to see them!", at: times[18]
m20 = post_message random,  jason,  "Happy Friday everyone!", at: times[19]

# Thread on Jason's question about threads
thread = Rooms::Thread.find_or_create_for(m5, creator: jason)
post_message thread, ashwin, "Yes! Threads are great for focused discussions.", at: times[5]
post_message thread, david,  "I've been using them for code reviews.", at: times[6]
post_message thread, jason,  "Nice, I'll start using them more.", at: times[7]

# Boosts
boost_message m1,  jason, "👋"
boost_message m1,  david, "🎉"
boost_message m3,  ashwin, "❤️"
boost_message m9,  ashwin, "🎉"
boost_message m9,  jason, "😂"
boost_message m18, ashwin, "🙌"
boost_message m18, jason,  "🔥"

# Bookmarks
bookmark_message m1,  david
bookmark_message m10, jason
bookmark_message m4,  jason
