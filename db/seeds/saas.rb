# SaaS development seed data
#
# Creates 3 global identities, 3 workspaces, each with rooms, messages, boosts, and bookmarks.
# Sign in as ashwin@sabha.co (OTP — check server logs for code)

# Global identities
gi_ashwin = GlobalIdentity.find_or_create_by!(email_address: "ashwin@sabha.co") do |gi|
  gi.name = "Ashwin M"
  gi.verified_at = Time.current
end
gi_ashwin.verify! unless gi_ashwin.verified?

gi_jason  = GlobalIdentity.find_or_create_by!(email_address: "jason@sabha.co") do |gi|
  gi.name = "Jason Fried"
  gi.verified_at = Time.current
end
gi_jason.verify! unless gi_jason.verified?

gi_david  = GlobalIdentity.find_or_create_by!(email_address: "david@sabha.co") do |gi|
  gi.name = "David Heinemeier Hansson"
  gi.verified_at = Time.current
end
gi_david.verify! unless gi_david.verified?

# Helper to seed a workspace with content
def seed_workspace(workspace, identities_and_roles)
  tenant_id = workspace.external_id.to_s

  # Create workspace memberships and users
  users_by_email = {}
  identities_and_roles.each do |gi, role|
    wm = gi.workspace_memberships.find_or_create_by!(tenant: tenant_id)
    ApplicationRecord.with_tenant(tenant_id) do
      user = User.unscoped.find_or_create_by!(email_address: gi.email_address) do |u|
        u.name = gi.name || gi.email_address.split("@").first.titleize
        u.role = role
        u.workspace_membership_id = wm.id
        u.verified_at = Time.current
      end
      wm.cache_user_id!(user.id) unless wm.user_id == user.id
      users_by_email[gi.email_address] = user
    end
  end

  # Yield users inside tenant context for content creation
  ApplicationRecord.with_tenant(tenant_id) do
    Current.user = users_by_email.values.first
    yield users_by_email if block_given?
  end
end

# Workspace 1: Basecamp — all 3 users
basecamp = Workspace.find_by(name: "Basecamp") || Workspace.create_with_database!(name: "Basecamp", creator: gi_ashwin)

seed_workspace(basecamp, [ [ gi_ashwin, :administrator ], [ gi_jason, :member ], [ gi_david, :member ] ]) do |users|
  ashwin   = users["ashwin@sabha.co"]
  jason    = users["jason@sabha.co"]
  david    = users["david@sabha.co"]
  everyone = [ ashwin, jason, david ]

  general = Rooms::Open.find_or_create_by!(name: "General") do |r|
    r.slug = "general"
    r.creator = ashwin
    r.auto_join = true
  end
  general.memberships.grant_to(everyone)

  random = Rooms::Open.find_or_create_by!(name: "Random") do |r|
    r.creator = jason
  end
  random.memberships.grant_to(everyone)

  design = Rooms::Closed.find_or_create_by!(name: "Design") do |r|
    r.creator = ashwin
  end
  design.memberships.grant_to([ ashwin, david ])

  dm = Rooms::Direct.find_or_create_for([ ashwin, jason ])

  times = spread_times(12)

  m1 = post_message general, ashwin, "Welcome to Basecamp chat!", at: times[0]
  m2 = post_message general, jason,  "Great to be here.", at: times[1]
  m3 = post_message general, david,  "Hello everyone!", at: times[2]
  m4 = post_message random,  jason,  "Anyone tried the new coffee place downstairs?", at: times[3]
  m5 = post_message random,  david,  "Yes! The cold brew is amazing.", at: times[4]
  m6 = post_message random,  ashwin, "/play tada", at: times[5]
  m7 = post_message design,  ashwin, "Let's review the new landing page mockups.", at: times[6]
  m8 = post_message design,  david,  "I've uploaded the latest versions.", at: times[7]
  m9 = post_message dm,      ashwin, "Quick sync about the roadmap?", at: times[8]
  m10 = post_message dm,     jason,  "Sure, let's chat after lunch.", at: times[9]
  m11 = post_message general, ashwin, "Reminder: all-hands at 3pm today.", at: times[10]
  m12 = post_message general, david,  "I'll be there!", at: times[11]

  boost_message m1, jason, "👋"
  boost_message m1, david, "🎉"
  boost_message m5, ashwin, "☕"
  boost_message m12, ashwin, "👍"

  bookmark_message m1, david
  bookmark_message m7, david
end

# Workspace 2: HEY — Jason + David
hey = Workspace.find_by(name: "HEY") || Workspace.create_with_database!(name: "HEY", creator: gi_jason)

seed_workspace(hey, [ [ gi_jason, :administrator ], [ gi_david, :member ] ]) do |users|
  jason = users["jason@sabha.co"]
  david = users["david@sabha.co"]

  general = Rooms::Open.find_or_create_by!(name: "General") do |r|
    r.slug = "general"
    r.creator = jason
    r.auto_join = true
  end
  general.memberships.grant_to([ jason, david ])

  times = spread_times(6)

  m1 = post_message general, jason, "Welcome to HEY's internal chat!", at: times[0]
  m2 = post_message general, david, "Excited to collaborate here.", at: times[1]
  m3 = post_message general, jason, "Let's keep things focused.", at: times[2]
  m4 = post_message general, david, "Agreed. Less noise, more signal.", at: times[3]

  dm = Rooms::Direct.find_or_create_for([ jason, david ])
  m5 = post_message dm, jason, "How's the email redesign going?", at: times[4]
  m6 = post_message dm, david, "Making good progress. Should be ready next week.", at: times[5]

  boost_message m1, david, "🚀"
  boost_message m4, jason, "💯"

  bookmark_message m1, david
end

# Workspace 3: ONCE — Ashwin + Jason
once = Workspace.find_by(name: "ONCE") || Workspace.create_with_database!(name: "ONCE", creator: gi_ashwin)

seed_workspace(once, [ [ gi_ashwin, :administrator ], [ gi_jason, :member ] ]) do |users|
  ashwin = users["ashwin@sabha.co"]
  jason  = users["jason@sabha.co"]

  general = Rooms::Open.find_or_create_by!(name: "General") do |r|
    r.slug = "general"
    r.creator = ashwin
    r.auto_join = true
  end
  general.memberships.grant_to([ ashwin, jason ])

  ops = Rooms::Closed.find_or_create_by!(name: "Operations") do |r|
    r.creator = ashwin
  end
  ops.memberships.grant_to([ ashwin, jason ])

  times = spread_times(6)

  m1 = post_message general, ashwin, "Welcome to the ONCE team chat.", at: times[0]
  m2 = post_message general, jason,  "Let's ship some software.", at: times[1]
  m3 = post_message ops,     ashwin, "Deployment checklist for next release.", at: times[2]
  m4 = post_message ops,     jason,  "I'll handle the staging environment.", at: times[3]
  m5 = post_message general, ashwin, "Great progress this week everyone.", at: times[4]
  m6 = post_message general, jason,  "Agreed, good momentum.", at: times[5]

  boost_message m2, ashwin, "🚀"
  boost_message m5, jason,  "🙌"

  bookmark_message m3, jason
end
