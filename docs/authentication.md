# Authentication System

This document describes how authentication works in Sabha.

## Overview

Sabha supports three self-hosted authentication methods, configured via the `AUTH_METHOD` environment variable:

| Method | `AUTH_METHOD=` | User Experience |
|--------|----------------|-----------------|
| **Password** | `password` (default) | Email + password |
| **OTP** | `otp` | Email → receive 6-digit code → enter code |
| **SSO** | `sso` | Redirect to parent app → return signed in |

Password and OTP require email verification for new users. SSO trusts the provider's verified email unless the provider sends `require_activation=true`, in which case Sabha sends its own verification email before opening a session.

## Configuration

### Environment Variables

```bash
# Authentication method: "password", "otp", or "sso"
AUTH_METHOD=password

# Required when AUTH_METHOD=sso
SSO_PROVIDER_URL=https://app.example.com/sso
SSO_SECRET=<shared-32+-char-secret>

# Optional SSO profile sync flags (default: false)
SSO_OVERRIDES_NAME=false
SSO_OVERRIDES_AVATAR=false

# Set by sabha_cloud on managed droplets to auto-bootstrap the first admin
# via SSO against sabha.co. Self-hosted operators should leave this unset.
AUTO_BOOTSTRAP=true
```

### How It Works

The `auth_method` is determined by `ENV["AUTH_METHOD"]`:

- If set to `"password"`, `"otp"`, or `"sso"`: uses that value
- If not set or invalid: defaults to `"password"`

```ruby
# app/models/account.rb
def auth_method
  ENV["AUTH_METHOD"].presence_in(VALID_AUTH_METHODS) || "password"
end
```

## Password Authentication

### Sign-Up Flow

```
User visits /join/{join_code}
  ↓
Fills form: name, email, password, avatar
  ↓
User.create! (with password_digest via bcrypt)
  ↓
Verification email sent (24-hour expiry)
  ↓
User clicks verification link
  ↓
Email verified → Session created → Redirected to chat
```

### Sign-In Flow

```
User visits /session/new
  ↓
Enters email + password
  ↓
User.authenticate_by (timing-attack safe)
  ↓
Email verified?
├─ No → "Please verify your email" error
└─ Yes → Session created → Redirected to chat
```

### Password Reset Flow

```
User clicks "Forgot your password?"
  ↓
Enters email → Reset email sent (1-hour expiry)
  ↓
User clicks reset link
  ↓
Enters new password (min 8 characters)
  ↓
Password updated + email verified → Session created
```

### Files

| File | Purpose |
|------|---------|
| `app/controllers/sessions_controller.rb` | Sign-in with password |
| `app/controllers/users_controller.rb` | Sign-up with password |
| `app/controllers/password_resets_controller.rb` | Password reset flow |
| `app/controllers/email_verifications_controller.rb` | Email verification |
| `app/views/sessions/new.html.erb` | Sign-in form (conditional) |
| `app/views/users/new.html.erb` | Sign-up form |
| `app/views/password_resets/*.html.erb` | Password reset forms |

---

## OTP Authentication (Passwordless)

### Sign-Up Flow

```
User visits /join/{join_code}
  ↓
Fills form: name, email, avatar (no password)
  ↓
User.create! (random password, never used)
  ↓
OTP code email sent (15-minute expiry)
  ↓
User enters 6-digit code
  ↓
Code validated → Email verified → Session created
```

### Sign-In Flow

```
User visits /session/new
  ↓
Enters email only
  ↓
AuthToken created (6-digit code + secure token)
  ↓
Email sent with 6-digit code
  ↓
User enters code at /auth_tokens/validations/new
  ↓
Code validated → Session created → Redirected to chat
```

### OTP Email Content

The OTP email contains only a 6-digit code (no magic link):

```
Your sign-in code for Sabha is: 123456

This code expires in 15 minutes.

If you did not request this, please ignore this email.
```

### AuthToken Model

```ruby
# app/models/auth_token.rb
class AuthToken < ApplicationRecord
  belongs_to :user
  has_secure_token :token  # For Sabha Cloud bootstrap only

  before_validation :generate_code

  scope :valid, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.lookup(token: nil, email_address: nil, code: nil)
    if token.present?
      return valid.find_by(token: token)  # Sabha Cloud bootstrap
    elsif email_address.present? && code.present?
      user = User.find_by(email_address: email_address)
      return valid.find_by(user: user, code: code)  # Regular OTP
    end
    nil
  end

  private

  def generate_code
    self.code = format("%06d", rand(100_000..999_999))
  end
end
```

### Files

| File | Purpose |
|------|---------|
| `app/controllers/auth_tokens_controller.rb` | Request OTP code |
| `app/controllers/auth_tokens/validations_controller.rb` | Validate OTP code |
| `app/models/auth_token.rb` | OTP token model |
| `app/mailers/auth_token_mailer.rb` | Send OTP email |
| `app/views/auth_token_mailer/otp.text.erb` | OTP email template |
| `app/views/auth_tokens/validations/new.html.erb` | Code entry form |

---

## SSO Authentication (DiscourseConnect)

When `AUTH_METHOD=sso`, Sabha acts as a DiscourseConnect consumer. Local password and OTP entry points redirect to `/session/sso`, which sends the browser to the parent app's SSO provider URL with a signed payload.

For setup instructions, provider implementation details, rollout guidance, and troubleshooting, see [Self-Hosted SSO](sso.md).

### Request Flow

```
User visits Sabha
  ↓
Unauthenticated request redirects to /session/sso
  ↓
Sabha creates a session-bound nonce
  ↓
Sabha redirects to SSO_PROVIDER_URL?sso=...&sig=...
  ↓
Parent app authenticates the user
  ↓
Parent app redirects back to /session/sso/callback?sso=...&sig=...
  ↓
Sabha verifies the signature and nonce
  ↓
User resolved/provisioned → Session created → Redirected to original page
```

### Provider Contract

The provider response must include:

| Field | Purpose |
|-------|---------|
| `nonce` | The nonce Sabha sent in the request |
| `external_id` | Stable immutable user id from the parent app |
| `email` | User email address |

Optional v1 fields:

| Field | Purpose |
|-------|---------|
| `name` | Used when creating users; can override when `SSO_OVERRIDES_NAME=true` |
| `avatar_url` | Used when creating users; can override when `SSO_OVERRIDES_AVATAR=true` |
| `require_activation` | When `true`, Sabha verifies email before opening a session |
| `failed` | When `true`, Sabha renders an auth failure without opening a session |
| `logout` | Signed local-session termination callback with a valid Sabha nonce |

### User Resolution

Sabha resolves SSO users in this order:

1. Existing `SingleSignOnRecord.external_id`
2. Existing user by email, only when `require_activation` is not true and the user has no SSO record
3. New user auto-provisioning

Roles, groups, usernames, 2FA fields, and custom fields are ignored in v1.

### Email Claiming Risk

Email matching is what makes SSO drop-in for existing installs, but it trusts the parent app's email verification. If the parent app lets someone use `foo@example.com` without verifying that address, that user could claim the existing Sabha account for `foo@example.com`.

Mitigations:

1. The provider must send `require_activation=true` for any unverified email. Sabha will send its own verification email and will not open a session until verification succeeds.
2. Operators can pre-seed `SingleSignOnRecord` mappings for existing users before enabling SSO.

---

## Initial Setup: Manual vs AutoBootstrap

There are two ways to set up a new Sabha instance:

### Manual First-Run (Default)

**For Kamal/self-hosted deployments.** No special configuration needed.

```
First visitor hits the site
  ↓
Redirected to /first_run (setup form)
  ↓
Enters name, email, password
  ↓
Admin account created → signed in → redirected to chat
```

The first visitor becomes the administrator. Subsequent visitors see the marketing page or login screen.

### AutoBootstrap (Sabha Cloud only)

AutoBootstrap is the provisioning mechanism Sabha Cloud uses on managed droplets. sabha_cloud sets `AUTO_BOOTSTRAP=true` plus the SSO env vars at droplet-creation time so the customer's sabha.co identity provisions the first admin on first visit — no setup form, no `ADMIN_*` env vars, no emailed magic link.

Self-hosted operators don't use this — they get the manual first-run form.

```bash
AUTO_BOOTSTRAP=true
SSO_PROVIDER_URL=https://sabha.co/session/sso
SSO_SECRET=<shared-32+-char-secret>
AUTH_METHOD=password                  # Or otp / sso — what the customer wants post-bootstrap
```

**Flow:**
```
First unauthenticated visitor hits any route
  ↓
Authentication#request_authentication sees should_auto_bootstrap?
  ↓
Redirect to /session/sso (handshake → sabha.co)
  ↓
sabha.co signs payload → /session/sso/callback
  ↓
Sso::CallbacksController calls FirstRun.auto_bootstrap_from_sso(payload):
  - Creates Account (named via Branding.app_name)
  - Creates admin User (role: administrator, verified) from payload
  - Creates SingleSignOnRecord linking external_id ↔ user
  - Creates "General" room with auto_join: true
  ↓
Session opened → redirected to root → welcome flash
```

AutoBootstrap is a one-shot ignition gated by `Account.none?`. After the first admin is provisioned, the droplet runs under whatever `AUTH_METHOD` the customer configured — `password`, `otp`, or persistent `sso`. Subsequent users sign in (or invite) per that method.

### Security Requirements

- `AUTO_BOOTSTRAP=true` requires `SSO_PROVIDER_URL` and `SSO_SECRET` — boot aborts in production otherwise (`config/initializers/00_boot_mode.rb`)
- The shared secret must match the provider's per-client secret
- Default is `false` — must explicitly set `AUTO_BOOTSTRAP=true`

### Files

| File | Purpose |
|------|---------|
| `app/models/first_run.rb` | Manual first-run + SSO auto-bootstrap logic |
| `app/controllers/first_runs_controller.rb` | Manual setup form (deflects to SSO under AUTO_BOOTSTRAP) |
| `app/controllers/sso/callbacks_controller.rb` | Invokes `auto_bootstrap_from_sso!` when `Account.none?` |
| `config/initializers/00_boot_mode.rb` | Boot-time env var validation |

---

## Session Management

### Session Model

Sessions track authenticated users across requests:

```ruby
# app/models/session.rb
class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour
  has_secure_token
  belongs_to :user
end
```

### Session Creation

```ruby
# app/controllers/concerns/authentication.rb
def start_new_session_for(user)
  user.sessions.start!(
    user_agent: request.user_agent,
    ip_address: request.remote_ip
  ).tap { |session| authenticated_as(session) }
end
```

### Cookie Configuration

```ruby
cookies.signed.permanent[:session_token] = {
  value: session.token,
  httponly: true,
  same_site: :lax
}
```

### Session Transfer (QR Code)

Users can transfer sessions between devices:

```ruby
# app/models/user/transferable.rb
TRANSFER_LINK_EXPIRY_DURATION = 4.hours

def transfer_id
  signed_id(purpose: :transfer, expires_in: TRANSFER_LINK_EXPIRY_DURATION)
end
```

---

## Email Verification

All new users must verify their email before accessing the app.

### Token Generation

Uses Rails 7.1+ `generates_token_for`:

```ruby
# app/models/user.rb
generates_token_for :email_verification, expires_in: 24.hours
generates_token_for :password_reset, expires_in: 1.hour
```

### Verification Methods

| Method | Purpose |
|--------|---------|
| `user.verified?` | Check if email verified |
| `user.verify_email!` | Mark email as verified |
| `user.send_verification_email` | Send verification link |

### Verification Enforcement

- **Password auth**: Unverified users blocked at sign-in
- **OTP auth**: Email verified when OTP code is validated

---

## Security Features

### Rate Limiting

| Endpoint | Limit |
|----------|-------|
| Password sign-in | 10 requests / 3 minutes |
| OTP request | 10 requests / 1 minute |
| OTP validation | 10 requests / 1 minute |
| SSO callback | 10 requests / 1 minute |
| Password reset request | 3 requests / 1 minute |
| Resend verification | 3 requests / 1 minute |

### Password Security

- Minimum 8 characters
- BCrypt hashing via `has_secure_password`
- Timing-attack safe via `authenticate_by`

### Token Security

- Cryptographically signed (Rails `generates_token_for`)
- Stateless (no database storage for verification tokens)
- Automatic expiry (24h email verification, 1h password reset)
- Tokens invalidated after use

---

## Routes

```ruby
# Authentication
resource :session                              # Password sign-in/out
get "/session/sso", to: "sso/handshakes#new"          # SSO provider redirect
get "/session/sso/callback", to: "sso/callbacks#show"
resources :auth_tokens, only: [:create]        # Request OTP
namespace :auth_tokens do
  resource :validations, only: [:new, :create] # Validate OTP
end
get "auth_tokens/validate/:token", to: "auth_tokens/validations#create", as: :sign_in_with_token

# Email verification
get "verify_email/:token", to: "email_verifications#show"
post "resend_verification", to: "email_verifications#resend"

# Password reset
resources :password_resets, only: [:new, :create, :edit, :update], param: :token

# Force password change (AutoBootstrap)
resource :change_password, only: [:show, :update]

# User registration
get "join/:join_code", to: "users#new"
post "join/:join_code", to: "users#create"

# First run setup
resource :first_run
```

---

## Database Schema

### Users Table (Authentication Fields)

```sql
email_address       VARCHAR NOT NULL UNIQUE
password_digest     VARCHAR          -- BCrypt hash
verified_at         DATETIME         -- Email verification timestamp
must_change_password BOOLEAN DEFAULT FALSE
last_authenticated_at DATETIME       -- Tracks first login
```

### Sessions Table

```sql
id           BIGINT PRIMARY KEY
user_id      BIGINT NOT NULL REFERENCES users(id)
token        VARCHAR NOT NULL UNIQUE
ip_address   VARCHAR
user_agent   VARCHAR
last_active_at DATETIME NOT NULL
```

### Auth Tokens Table

```sql
id         BIGINT PRIMARY KEY
user_id    BIGINT NOT NULL REFERENCES users(id)
token      VARCHAR NOT NULL UNIQUE  -- Secure token (Sabha Cloud)
code       VARCHAR NOT NULL         -- 6-digit OTP code
expires_at DATETIME NOT NULL        -- 15 minutes from creation
used_at    DATETIME                 -- When code was used
```

### Single Sign-On Records Table

```sql
user_id        BIGINT NOT NULL UNIQUE REFERENCES users(id)
external_id    VARCHAR NOT NULL UNIQUE
external_email VARCHAR
last_payload   TEXT
last_seen_at   DATETIME
```

---

## Deployment Scenarios

### Default (Self-Hosted)

```bash
AUTH_METHOD=password  # or omit for default
```

- Password-based authentication
- Manual first-run setup
- Email verification required

### Passwordless Community

```bash
AUTH_METHOD=otp
```

- OTP code authentication (no passwords)
- 6-digit code sent via email
- Email verification via OTP validation

### Parent-App SSO

```bash
AUTH_METHOD=sso
SSO_PROVIDER_URL=https://app.example.com/sso
SSO_SECRET=<shared-32+-char-secret>
```

- DiscourseConnect-compatible signed SSO
- Parent app owns authentication
- Sabha auto-provisions users on first valid SSO callback
- Password and OTP login forms are disabled

### Sabha Cloud Managed

```bash
AUTO_BOOTSTRAP=true
SSO_PROVIDER_URL=https://sabha.co/session/sso
SSO_SECRET=<shared-32+-char-secret>
AUTH_METHOD=password    # Or otp / sso — whatever the customer wants post-bootstrap
```

Set by sabha_cloud on every managed droplet — not a self-hosted option.

- First visit bounces through sabha.co; the customer's sabha.co identity becomes the admin
- One-shot bootstrap gated by `Account.none?` — no magic-link emails, no `ADMIN_*` env vars
- Subsequent users sign in via `AUTH_METHOD`

---

## File Reference

### Controllers

| File | Purpose |
|------|---------|
| `sessions_controller.rb` | Password sign-in/out |
| `sso_controller.rb` | DiscourseConnect request and callback |
| `auth_tokens_controller.rb` | Request OTP code |
| `auth_tokens/validations_controller.rb` | Validate OTP code |
| `users_controller.rb` | User registration |
| `first_runs_controller.rb` | Initial setup |
| `email_verifications_controller.rb` | Email verification |
| `password_resets_controller.rb` | Password reset |
| `change_passwords_controller.rb` | Force password change |
| `sessions/transfers_controller.rb` | QR code session transfer |

### Models

| File | Purpose |
|------|---------|
| `user.rb` | User authentication, tokens, verification |
| `session.rb` | Session management |
| `auth_token.rb` | OTP codes |
| `single_sign_on_record.rb` | Parent-app identity mapping, lookup, claim, and provisioning |
| `single_sign_on_nonce.rb` | Database-backed SSO nonce issue and replay protection |
| `account.rb` | Auth method configuration |
| `first_run.rb` | AutoBootstrap |

### Concerns

| File | Purpose |
|------|---------|
| `authentication.rb` | Session handling, authentication flow |
| `user/transferable.rb` | QR code session transfer |
| `force_password_change.rb` | Password change enforcement |

### Mailers

| File | Purpose |
|------|---------|
| `auth_token_mailer.rb` | OTP code email |
| `user_mailer.rb` | Email verification, password reset |
