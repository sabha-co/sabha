# Authentication System

This document describes how authentication works in Campfire-CE.

## Overview

Campfire-CE supports two authentication methods, configured via the `AUTH_METHOD` environment variable:

| Method | `AUTH_METHOD=` | User Experience |
|--------|----------------|-----------------|
| **Password** | `password` (default) | Email + password |
| **OTP** | `otp` | Email → receive 6-digit code → enter code |

Both methods require email verification for new users.

## Configuration

### Environment Variables

```bash
# Authentication method: "password" or "otp"
AUTH_METHOD=password

# Auto-bootstrap for headless deployments (see "AutoBootstrap" section)
AUTO_BOOTSTRAP=true
ADMIN_EMAIL=admin@example.com
ADMIN_NAME=Administrator
ADMIN_AUTH_TOKEN=<32+-char-token> # For Campfire Cloud only
```

### How It Works

The `auth_method_value` is determined by `ENV["AUTH_METHOD"]`:

- If set to `"password"` or `"otp"`: uses that value
- If not set or invalid: defaults to `"password"`

```ruby
# app/models/account.rb
def auth_method_value
  value = ENV["AUTH_METHOD"] || "password"
  value.in?(VALID_AUTH_METHODS) ? value : "password"
end
```

---

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
Your sign-in code for Campfire is: 123456

This code expires in 15 minutes.

If you did not request this, please ignore this email.
```

### AuthToken Model

```ruby
# app/models/auth_token.rb
class AuthToken < ApplicationRecord
  belongs_to :user
  has_secure_token :token  # For Campfire Cloud bootstrap only

  before_validation :generate_code

  scope :valid, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.lookup(token: nil, email_address: nil, code: nil)
    if token.present?
      return valid.find_by(token: token)  # Campfire Cloud bootstrap
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

## Initial Setup: Manual vs AutoBootstrap

There are two ways to set up a new Campfire instance:

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

### AutoBootstrap (Campfire Cloud Only)

**For managed hosting platforms** where the deployment is controlled programmatically.

AutoBootstrap enables headless account creation without user interaction. The hosting platform:
1. Generates credentials before deployment
2. Sets environment variables
3. Sends welcome email with one-time login link
4. User clicks link to authenticate (no password needed)

```bash
AUTO_BOOTSTRAP=true
ADMIN_EMAIL=user@example.com
ADMIN_NAME=Administrator           # Optional, defaults to "Administrator"
ADMIN_AUTH_TOKEN=<32+-char-token>  # One-time login token
AUTH_METHOD=otp                    # Recommended for Cloud
```

**Flow:**
```
First visitor hits the site
  ↓
AutoBootstrap triggered (no setup form)
  ↓
Admin account created with auth token
  ↓
User receives welcome email with login link
  ↓
Clicks link → /auth_tokens/validate/{token}
  ↓
Token validated → session created → redirected to chat
  ↓
Subsequent logins use OTP (6-digit code via email)
```

**When to use AutoBootstrap:**
- ✅ Campfire Cloud managed deployments
- ❌ Kamal/self-hosted (use manual first_run instead)

### Security Requirements

- `ADMIN_AUTH_TOKEN` must be at least 32 characters
- Tokens expire after 24 hours
- Tokens are single-use (invalidated after login)
- Default is `false` - must explicitly set `AUTO_BOOTSTRAP=true`

### Files

| File | Purpose |
|------|---------|
| `app/models/first_run.rb` | Manual and AutoBootstrap logic |
| `app/controllers/first_runs_controller.rb` | Manual setup form |
| `app/controllers/marketing_controller.rb` | Triggers AutoBootstrap |
| `config/routes.rb` | `sign_in_with_token` route |

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
token      VARCHAR NOT NULL UNIQUE  -- Secure token (Campfire Cloud)
code       VARCHAR NOT NULL         -- 6-digit OTP code
expires_at DATETIME NOT NULL        -- 15 minutes from creation
used_at    DATETIME                 -- When code was used
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

### Campfire Cloud Managed

```bash
AUTO_BOOTSTRAP=true
ADMIN_EMAIL=user@example.com
ADMIN_AUTH_TOKEN=<secure-32+-char-token>
AUTH_METHOD=otp
```

- Automated account creation
- One-time login link for initial setup
- OTP for subsequent logins

### Paid Community (with Gumroad)

```bash
GUMROAD_ON=true
GUMROAD_ACCESS_TOKEN=...
GUMROAD_PRODUCT_IDS=...
AUTH_METHOD=password
```

- Payment verification at sign-up
- Works with either auth method

---

## File Reference

### Controllers

| File | Purpose |
|------|---------|
| `sessions_controller.rb` | Password sign-in/out |
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

---

## Related Documentation

- [ENV-Based Auth Configuration](./env-based-auth-configuration.md) - Detailed ENV setup
