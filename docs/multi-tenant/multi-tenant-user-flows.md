# Multi-Tenant User Flows (SaaS Mode)

Detailed user flows for Sabha in **multi-tenant (SaaS)** mode.

**Related Documents:**
- [Product PRD](./multi-tenancy-product-prd.md) - Business goals, user stories, requirements
- [Technical PRD](./multi-tenancy-technical-prd.md) - Architecture and requirements
- [Implementation Tasks](./multi-tenancy-plans-and-tasks.md) - Task breakdown
- [Architecture Notes](./multitenant-saas-notes.md) - Fizzy comparison and patterns

---

## Overview

| Aspect | Multi-Tenant (SaaS) |
|--------|---------------------|
| Workspaces | Multiple (database-per-workspace) |
| GlobalIdentity model | Cross-workspace identity (untenanted DB) |
| User model | Workspace-specific profile + permissions |
| Auth method | **OTP code only** (no passwords) |
| Session | GlobalSession belongs to GlobalIdentity |
| Account model | Settings per workspace |
| Workspace selector | Sidebar within workspace (not separate page) |

---

## Key Models

| Model | Database | Purpose |
|-------|----------|---------|
| `GlobalIdentity` | Untenanted | Cross-workspace user identity (email only) |
| `GlobalSession` | Untenanted | Authentication session (30-day cookie) |
| `AuthCode` | Untenanted | 6-char OTP codes (15-min expiry) |
| `Workspace` | Untenanted | Workspace registry (name, external_id) |
| `WorkspaceMembership` | Untenanted | Links GlobalIdentity ↔ Workspace |
| `User` | Per-workspace | Workspace-specific identity + permissions |
| `Account` | Per-workspace | Workspace settings (singleton) |

---

## Root Page Flow

The root page (`/`) redirects based on authentication state:

```
┌─────────────────────────────────────────────────────────────────┐
│ Unauthenticated User visits /                                   │
├─────────────────────────────────────────────────────────────────┤
│ → Redirect to /session/new (sign in page)                       │
│ → User can click "Create an account" to go to /registration/new │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Authenticated User visits /                                     │
├─────────────────────────────────────────────────────────────────┤
│ → If 1+ workspaces: redirect to most recent workspace           │
│   → Workspace switching via sidebar menu (no separate page)     │
│ → If NO workspaces: redirect to /workspaces/new (create form)   │
└─────────────────────────────────────────────────────────────────┘
```

**Key principle:** Always redirect authenticated users directly into a workspace. Workspace switching happens via sidebar within the app, not a separate selector page.

**Key URLs:**
- `/` - Landing (redirects based on auth state)
- `/session/new` - Sign in form
- `/registration/new` - Sign up form
- `/auth_code` - OTP code entry
- `/workspaces/new` - Create workspace form (only for users with no workspaces)
- `/join/{code}` - Join workspace via code
- `/profile/edit` - Edit email address

---

## 1. New User Sign Up (OTP Only)

**Trigger:** User visits site and creates an account

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits / (root page)                                    │
│ 2. Redirected to /session/new                                   │
│ 3. Clicks "Create an account" → /registration/new               │
│    - return_to param preserved if present                       │
│ 4. Enters email (no password - OTP only)                        │
│ 5. System creates GlobalIdentity in untenanted DB               │
│ 6. AuthCode created (6-char alphanumeric, 15-min expiry)        │
│ 7. Email sent via AuthCodeMailer                                │
│ 8. Redirected to /auth_code                                     │
│ 9. User enters code                                             │
│ 10. AuthCode.consume(code) returns GlobalIdentity, destroys code│
│ 11. GlobalIdentity.verify! sets verified_at                     │
│ 12. GlobalSession created, cookie set (global_session_token)    │
│ 13. Redirect to after_authentication_url:                       │
│     - Respects return_to from session (e.g., join page)         │
│     - Default: / → LandingController                            │
│ 14. LandingController checks workspaces:                        │
│     - If 1+ workspaces: redirect to most recent workspace       │
│     - If 0 workspaces: redirect to /workspaces/new              │
│ 15. New user sees "Create workspace" form                       │
└─────────────────────────────────────────────────────────────────┘

Note: "Sign in" link preserves return_to when switching to sign-in page.
```

**Database changes:**
```ruby
# Untenanted DB
global_identity = GlobalIdentity.create!(
  email_address: "user@example.com",
  verified_at: nil  # Set after OTP verification
)

auth_code = AuthCode.create!(
  global_identity: global_identity,
  code: OtpCode.generate(6),  # e.g., "X7K9M2"
  purpose: :sign_up,
  expires_at: 15.minutes.from_now
)

# After OTP verification:
global_identity = AuthCode.consume(params[:code])  # Returns identity, destroys code
global_identity.verify!  # Sets verified_at = Time.current

global_session = GlobalSession.create!(
  global_identity: global_identity,
  user_agent: request.user_agent,
  ip_address: request.remote_ip,
  expires_at: 30.days.from_now
  # token auto-generated via has_secure_token (40 chars)
)

# Cookie set (permanent - expiry enforced server-side via GlobalSession.expires_at):
cookies.signed.permanent[:global_session_token] = {
  value: global_session.token,
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax
}
```

**No User created yet** - user has no workspace to belong to.

---

## 2. Sign In (Existing Account)

**Trigger:** User visits sign in page

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits /session/new                                     │
│    - If return_to param present, stored in session              │
│ 2. Enters email                                                 │
│ 3. If GlobalIdentity exists:                                    │
│    - AuthCode created (purpose: :sign_in)                       │
│    - Email sent with 6-char code                                │
│ 4. If GlobalIdentity doesn't exist:                             │
│    - Same message shown (prevent email enumeration)             │
│    - No email sent                                              │
│ 5. Redirect to /auth_code                                       │
│ 6. User enters code                                             │
│ 7. AuthCode.consume(code)                                       │
│ 8. GlobalSession created, cookie set                            │
│ 9. Redirect to after_authentication_url:                        │
│    - Respects return_to from session (e.g., /1000001/join/abc)  │
│    - Default: / → LandingController → most recent workspace     │
└─────────────────────────────────────────────────────────────────┘

Note: "Create one" link preserves return_to when switching to signup.
```

**Security features:**
- Rate limited: 10 attempts per 3 minutes
- Email enumeration prevention: Same message for existing/non-existing accounts
- Session fixation prevention: `reset_session` called on login
- OTP codes are typo-tolerant (O→0, I/L→1)

---

## 3. Create Workspace

**Trigger:** New user with no workspaces, or user clicks "Create Workspace" in sidebar

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User (authenticated) is redirected to /workspaces/new        │
│    (automatic if no workspaces, or via sidebar menu)            │
│ 3. Enters workspace name (e.g., "Acme Corp")                    │
│ 4. Workspace.create_with_database! is called:                   │
│    a. external_id generated (7+ digit, e.g., 1000001)           │
│    b. Workspace created in untenanted DB                        │
│    c. Workspace SQLite database file created                    │
│    d. WorkspaceMembership created (GlobalIdentity → Workspace)  │
│    e. Within tenant context:                                    │
│       - Account created (singleton, workspace settings)         │
│       - User created (role: :administrator)                     │
│       - "General" room created (Rooms::Open)                    │
│    f. user_id cached in WorkspaceMembership                     │
│ 5. Redirect to /1000001 (workspace home)                        │
└─────────────────────────────────────────────────────────────────┘
```

**Database changes:**
```ruby
# Untenanted DB
workspace = Workspace.create!(
  external_id: Workspace::ExternalIdSequence.next_id,  # e.g., 1000001
  name: "Acme Corp",
  creator_id: current_global_identity.id
)

# Untenanted DB - create WorkspaceMembership
workspace_membership = current_global_identity.workspace_memberships.create!(
  tenant: workspace.external_id.to_s
)

# Workspace DB (storage/{env}/workspaces/1000001/main.sqlite3)
ApplicationRecord.with_tenant(workspace.external_id) do
  account = Account.create!(name: workspace.name)

  # Direct User creation (NOT using create_user!)
  admin_user = User.find_or_initialize_by(email_address: creator.email_address)
  if admin_user.new_record?
    admin_user.assign_attributes(
      workspace_membership_id: membership.id,
      name: creator.email_address.split("@").first.titleize,  # Titleized!
      role: :administrator,
      verified_at: Time.current  # Set immediately
    )
    admin_user.save!
  end

  # Cache user_id for fast lookup
  workspace_membership.cache_user_id!(user.id)

  # Create default room
  Rooms::Open.create!(name: "General", slug: "general", creator: user)
end
```

---

## 4. Join Workspace via Join Code

**Trigger:** User has a join code URL (e.g., `/join/abc123xyz`)

The join flow reuses the same `UsersController` and nametag UI as self-hosted mode, with SaaS-specific handling for authentication.

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Global join URL validation                              │
├─────────────────────────────────────────────────────────────────┤
│ 1. User visits /join/abc123xyz (global route)                   │
│ 2. Saas::WorkspacesController#join handles the request          │
│ 3. Workspace.find_by_join_code(code) validates code             │
│ 4. If valid: redirect to /{workspace_id}/join/abc123xyz         │
│    If invalid: redirect to login/workspaces with error          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Workspace-scoped join page (UsersController#new)        │
├─────────────────────────────────────────────────────────────────┤
│ Shows nametag UI with workspace name, member counts, etc.       │
│                                                                 │
│ Case A: User is NOT authenticated (no GlobalSession)            │
│   - Shows "Sign in to join" button                              │
│   - Shows "Create one" link for signup                          │
│   - Both include return_to=/{workspace_id}/join/abc123xyz       │
│   - return_to is preserved when switching between sign-in/signup│
│                                                                 │
│ Case B: User is authenticated (has GlobalSession)               │
│   - Shows "Joining as {email}" message                          │
│   - Shows "Join {workspace_name}" button (one-click, no form)   │
│   - Name defaults to email prefix (e.g., "bob" for bob@ex.com)  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Complete join (UsersController#create)                  │
├─────────────────────────────────────────────────────────────────┤
│ 1. User clicks "Join" (POST /{workspace_id}/join/abc123xyz)     │
│ 2. WorkspaceMembership created (GlobalIdentity → Workspace)     │
│ 3. User record created with email prefix as name                │
│ 4. Join code redeemed                                           │
│ 5. Redirect to workspace root (/{workspace_id})                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key implementation details:**
- Global `/join/{code}` route → `Saas::WorkspacesController#join` (validates code, redirects)
- Workspace-scoped `/{workspace_id}/join/{code}` route → `UsersController` (same as self-hosted)
- `UsersController` detects SaaS mode via `saas_authenticated?` and `saas_unauthenticated?` helpers
- Session's `return_to_after_authenticating` is preserved across `reset_session` (session fixation prevention)
- Sign-in/sign-up pages preserve `return_to` param when linking to each other
- Authenticated users see one-click join (no name field required)

**Database changes:**
```ruby
# In UsersController#create_for_saas_user:
global_identity = Current.global_identity

# Create records first to avoid burning limited-use invites on failures
membership = WorkspaceMembership.create!(
  global_identity: global_identity,
  tenant: ApplicationRecord.current_tenant
)

# Create User in workspace database (name defaults to email prefix)
user = membership.create_user!

# Redeem join code after successful creation
# If redemption fails, cleanup the records we just created
unless @join_code.redeem
  user.destroy!
  membership.destroy!
  redirect_to root_url, alert: "This invite link is no longer valid."
  return
end

redirect_to root_url
```

**Note:** Join users are created via `WorkspaceMembership#create_user!` which differs from workspace creator:
| Attribute | Workspace Creator | Join User |
|-----------|-------------------|-----------|
| name | Titleized email prefix | Raw email prefix |
| role | `:administrator` | `:member` |
| verified_at | `Time.current` | `nil` |

---

## 5. First Workspace Access (Lazy User Creation Fallback)

**Trigger:** User enters a workspace where they have a WorkspaceMembership but no User record yet

**Note:** For the join flow (Section 4), User records are now created immediately during join. This lazy creation is a fallback for edge cases (e.g., WorkspaceMembership created via API/script without User).

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits /1000001/rooms/general                           │
│ 2. PathRewriter middleware:                                     │
│    - Extracts workspace_id from URL (1000001)                   │
│    - Sets SCRIPT_NAME=/1000001, PATH_INFO=/rooms/general        │
│    - Stashes workspace_id in env["sabha.workspace_id"]       │
│ 3. TenantSelector middleware:                                   │
│    - Sets ApplicationRecord.current_tenant = "1000001"          │
│ 4. Authentication flow (resume_session):                        │
│    - Finds GlobalSession by global_session_token cookie         │
│    - Sets Current.global_session                                │
│    - Looks up WorkspaceMembership for this tenant               │
│    - Sets Current.workspace_membership                          │
│ 5. ensure_workspace_user_exists check:                          │
│    - If workspace_membership.user_id is nil:                    │
│      - Creates User record in workspace DB                      │
│      - Caches user_id in WorkspaceMembership                    │
│ 6. Current.user now returns the workspace-specific User         │
│ 7. Request proceeds to controller                               │
└─────────────────────────────────────────────────────────────────┘
```

**Database changes (on first access):**
```ruby
# In Authentication concern, ensure_workspace_user_exists:
if Current.workspace_membership.present? && Current.workspace_membership.user_id.blank?
  Current.workspace_membership.create_user!
end

# WorkspaceMembership#create_user! implementation:
def create_user!(name: nil, role: :member)
  ApplicationRecord.with_tenant(tenant) do
    user = User.find_or_create_by!(email_address: global_identity.email_address) do |u|
      u.workspace_membership_id = id
      u.name = name || global_identity.email_address.split("@").first  # No titleization
      u.role = role  # Default :member
      # Note: verified_at is NOT set (user can still access workspace)
    end
    cache_user_id!(user.id) unless user_id == user.id
    user
  end
end

# Differences from workspace creator:
# - No name titleization
# - No verified_at set
# - Role defaults to :member (not :administrator)
```

---

## 6. Switch Workspace (via Sidebar)

**Trigger:** User opens workspace switcher in sidebar

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User is in /1000001/rooms/general (Workspace A)              │
│ 2. Opens workspace switcher sidebar (right side)                │
│    - Shows list of all user's workspaces                        │
│    - Shows "Create workspace" option                            │
│ 3. Clicks "Workspace B" (external_id: 1000002)                  │
│ 4. Navigate to /1000002                                         │
│ 5. PathRewriter/TenantSelector set new tenant context           │
│ 6. GlobalSession cookie still valid (domain-level)              │
│ 7. WorkspaceMembership looked up for new tenant                 │
│ 8. Current.user now returns User from Workspace B               │
│ 9. Workspace B home rendered                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Key points:**
- Workspace switching via sidebar menu, not separate page
- GlobalSession cookie is domain-level - no re-authentication needed
- Only the User record changes when switching workspaces

---

## 7. Logout

**Trigger:** User clicks "Sign out"

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User clicks "Sign out" (DELETE /session)                     │
│ 2. GlobalSession destroyed                                      │
│ 3. global_session_token cookie cleared                          │
│ 4. Redirect to /session/new                                     │
│ 5. User is logged out of ALL workspaces (single session)        │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation:** Domain-level cookie with single GlobalSession. Logout = logout everywhere.

---

## 8. Profile Management (Email Change)

**Trigger:** User visits /profile/edit

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User visits /profile/edit                                    │
│ 2. Enters new email address                                     │
│ 3. If email already taken → error                               │
│ 4. GlobalIdentity.email_address updated                         │
│ 5. GlobalIdentity.verified_at set to nil (requires re-verify)   │
│ 6. AuthCode created for new email                               │
│ 7. User signed out (security)                                   │
│ 8. Redirect to /auth_code                                       │
│ 9. User must verify new email to continue                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Current Context Flow

How `Current` attributes flow through the system:

```ruby
# Outside workspace context (/, /workspaces/new, /session/new):
Current.global_session        # GlobalSession from cookie
Current.global_identity       # global_session.global_identity
Current.workspace_membership  # nil (no tenant context)
Current.workspace             # nil
Current.user                  # nil

# Inside workspace context (/1000001/rooms/general):
Current.global_session        # GlobalSession from cookie
Current.global_identity       # global_session.global_identity
Current.workspace_membership  # WorkspaceMembership for this tenant
Current.workspace             # Workspace record (lazy-loaded)
Current.user                  # workspace_membership.user (workspace-specific)
```

---

## Session & Cookie Strategy

```
Cookie: global_session_token
- Domain-level (not path-scoped)
- Permanent cookie (no browser-side expiration)
- Expiry enforced server-side via GlobalSession.expires_at (30 days of inactivity)
- httponly: true
- secure: true (production)
- same_site: :lax

Pros:
- Single login for all workspaces
- Simpler implementation
- Better UX

Cons:
- Logout = logout everywhere (acceptable trade-off)
```

---

## Rate Limiting

| Endpoint | Limit |
|----------|-------|
| POST /session (email submit) | 10 per 3 minutes |
| POST /registration | 10 per 3 minutes |
| POST /auth_code | 10 per 15 minutes |

---

## Edge Cases

### 1. User Already in Workspace Tries to Join Again
- `find_or_create_by!` prevents duplicates
- Redirect to workspace (no error)

### 2. Administrator Tries to Leave (Only Admin)
- Tracked in MVP-13 (Workspace Membership Management)
- Should prevent if only administrator
- Must transfer ownership or delete workspace first

### 3. Invalid/Expired Join Code
- Unauthenticated user: Redirect to `/session/new` with error message
- Authenticated user: Redirect to `/workspaces` with error message
- Error message: "Invalid or expired join code."

### 4. Invalid/Expired Auth Code
- Shows: "Invalid or expired code. Please try again."
- Redirect back to /auth_code

### 5. GlobalIdentity Exists, No Workspaces
- Redirect to /workspaces/new (create workspace form)
- Can also join via /join/{code} if they have a link

### 6. Email Already Registered (Sign Up)
- Security: Don't reveal if email exists
- Creates AuthCode with purpose: :sign_in (not :sign_up)
- User effectively signs in instead of signing up
- Same message: "Check your email for a verification code"

---

## Key Files

### Controllers
- `saas/app/controllers/saas/landing_controller.rb` - Root redirects
- `saas/app/controllers/saas/sessions_controller.rb` - Sign in
- `saas/app/controllers/saas/registrations_controller.rb` - Sign up
- `saas/app/controllers/saas/auth_codes_controller.rb` - OTP verification
- `saas/app/controllers/saas/workspaces_controller.rb` - Workspace mgmt & join code validation
- `saas/app/controllers/saas/profiles_controller.rb` - Email change
- `app/controllers/users_controller.rb` - Join flow (shared with self-hosted, SaaS-aware)

### Models (Untenanted)
- `saas/app/models/global_identity.rb` - Cross-workspace identity
- `saas/app/models/global_session.rb` - Auth session
- `saas/app/models/auth_code.rb` - OTP codes
- `saas/app/models/workspace.rb` - Workspace registry
- `saas/app/models/workspace_membership.rb` - Identity ↔ Workspace link

### Authentication
- `saas/app/controllers/concerns/saas/authentication.rb` - SaaS auth helpers
- `app/controllers/concerns/authentication.rb` - Core auth (ensure_workspace_user_exists)
- `app/models/current.rb` - Current context

### Middleware
- `saas/lib/sabha/saas/path_rewriter.rb` - URL → tenant extraction
- `saas/config/initializers/tenanting/tenant_resolver.rb` - Tenant context setup
