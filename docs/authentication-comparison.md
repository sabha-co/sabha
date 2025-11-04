# Authentication Flow Comparison: Once-Campfire vs Smallbets-CE

**Document Version:** 1.0
**Date:** 2025-11-04
**Author:** System Analysis

---

## Executive Summary

| Aspect | **Once-Campfire** | **Smallbets-CE** |
|--------|------------------|------------------|
| **Primary Auth Method** | Password-based | Passwordless OTP (One-Time Password) |
| **Sign-up Gate** | Join code only | Join code + Gumroad payment verification |
| **Initial Setup** | First-run admin creation | First-run admin creation |
| **New User Flow** | Direct registration with password | Email verification → Gumroad check → Auto-login |
| **Sign-in Methods** | 1. Password<br>2. Session transfer | 1. OTP (6-digit code)<br>2. Magic link<br>3. Session transfer<br>4. Password (admin only) |
| **Payment Integration** | None | Gumroad API + webhooks |
| **User States** | Active/Inactive | Active/Inactive/Suspended (refunds) |

---

## Table of Contents

1. [Sign-up Flow Comparison](#1-sign-up-flow-comparison)
2. [Sign-in Flow Comparison](#2-sign-in-flow-comparison)
3. [Session Management](#3-session-management)
4. [User Model Differences](#4-user-model-differences)
5. [Authentication Mechanisms](#5-authentication-mechanisms)
6. [Security Features](#6-security-features)
7. [Gumroad Integration](#7-gumroad-integration-smallbets-ce-only)
8. [Access Control](#8-access-control)
9. [Critical Code Differences](#9-critical-code-differences)
10. [Migration Path](#10-migration-path)
11. [Recommendations](#11-recommendations)
12. [File Reference](#12-file-reference)

---

## 1. Sign-up Flow Comparison

### A. Initial Setup (First Run)

**STATUS: 🟢 IDENTICAL**

Both systems use the exact same first-run setup:

```ruby
# Both: app/models/first_run.rb (identical code)
class FirstRun
  ACCOUNT_NAME = "Campfire"  # or customized in Smallbets-CE
  FIRST_ROOM_NAME = "All Talk"

  def self.create!(user_params)
    account = Account.create!(name: ACCOUNT_NAME)
    room    = Rooms::Open.new(name: FIRST_ROOM_NAME)
    administrator = room.creator = User.new(user_params.merge(role: :administrator))
    room.save!
    room.memberships.grant_to administrator
    administrator
  end
end
```

**Process:**
1. First visitor becomes administrator
2. Creates account + first open room ("All Talk")
3. Auto-login after setup
4. No payment or verification required

**Files:**
- Controller: `app/controllers/first_runs_controller.rb`
- View: `app/views/first_runs/show.html.erb`
- Route: `GET/POST /first_run`

---

### B. New User Registration

**STATUS: 🔴 MAJOR DIFFERENCES**

#### Once-Campfire: Simple Join

**URL:** `/join/{join_code}`

**Form Fields:**
- Name (required)
- Email (required)
- Password (required)
- Avatar (optional)

**Process:**
```ruby
# once-campfire/app/controllers/users_controller.rb:8-13
def create
  @user = User.create!(user_params)
  start_new_session_for @user
  redirect_to root_url
rescue ActiveRecord::RecordNotUnique
  redirect_to new_session_url(email_address: user_params[:email_address])
end
```

**Flow:**
```
User clicks join link
  ↓
Verify join code matches
  ↓
User fills form (name, email, password, avatar)
  ↓
Create user record
  ↓
Auto-login with new session
  ↓
Redirect to chat
```

---

#### Smallbets-CE: Gumroad-Gated Join

**URL:** `/join/{join_code}`

**Form Fields:**
- Name (required)
- Email (required)
- Avatar (optional)
- ❌ No password field

**Process:**
```ruby
# smallbets-ce/app/controllers/users_controller.rb:14-31
def create
  @user = User.from_gumroad_sale(user_params)  # ← Gumroad verification

  if @user.nil?
    redirect_to account_join_code_url, alert: "We couldn't find a sale for that email."
    return
  end

  deliver_webhooks_to_bots(@user, :created) if @user.previously_new_record?

  if @user.previously_new_record? || @user.imported_from_gumroad_and_unclaimed?
    start_new_session_for @user
    redirect_to root_url
  else
    start_otp_for @user  # ← Existing user gets OTP
    redirect_to new_auth_tokens_validations_path
  end
end
```

**Gumroad Verification Logic:**
```ruby
# smallbets-ce/app/models/user.rb:78-89
def self.from_gumroad_sale(params)
  return new(params) unless ENV["GUMROAD_ON"] == "true"

  sale = GumroadAPI.successful_membership_sale(email: params[:email_address])
  return nil unless sale

  find_or_initialize_by(email_address: params[:email_address]).tap do |user|
    user.assign_attributes(params)
    user.order_id = sale["order_id"]
    user.membership_started_at = sale["created_at"]
    user.save!
  end
end
```

**Flow:**
```
User clicks join link
  ↓
Verify join code matches
  ↓
User fills form (name, email, avatar)
  ↓
Call Gumroad API to verify purchase
  ↓
Purchase found?
  ├─ No → Redirect with error
  ↓
  └─ Yes → Continue
      ↓
      User already exists?
      ├─ No → Create user + auto-login
      ├─ Yes, never logged in → Claim account + auto-login
      └─ Yes, has logged in → Trigger OTP flow
```

**Key Differences:**
| Feature | Once-Campfire | Smallbets-CE |
|---------|--------------|-------------|
| Password required | ✅ Yes | ❌ No |
| Payment check | ❌ No | ✅ Gumroad API |
| Existing user handling | Redirect to sign-in | Trigger OTP flow |
| User pre-import | ❌ No | ✅ Via webhooks |

---

## 2. Sign-in Flow Comparison

**STATUS: 🔴 COMPLETELY DIFFERENT**

### Once-Campfire: Password-Based

**Route:** `POST /session`

**View:** Password entry form with email + password fields

**Code:**
```ruby
# once-campfire/app/controllers/sessions_controller.rb:10-16
def create
  if user = User.active.authenticate_by(email_address: params[:email_address],
                                        password: params[:password])
    start_new_session_for user
    redirect_to post_authenticating_url
  else
    render_rejection :unauthorized
  end
end
```

**Flow:**
```
User visits /session/new
  ↓
Enter email + password
  ↓
BCrypt authentication
  ↓
Valid? → Create session, redirect
Invalid? → Show error, render form again
```

**Features:**
- ✅ Immediate authentication (single step)
- ✅ Works offline (no email needed)
- ✅ Rate limited (10 attempts / 3 minutes)
- ❌ Password to remember
- ❌ No password reset flow (contact admin)

---

### Smallbets-CE: Passwordless OTP

**Routes:**
- `POST /auth_tokens` (request OTP)
- `POST /auth_tokens/validations` (validate OTP)
- `GET /auth_tokens/validate/:token` (magic link)

#### Step 1: Request OTP

**View:** Email entry form (no password field)

**Code:**
```ruby
# smallbets-ce/app/controllers/auth_tokens_controller.rb:8-14
def create
  user = User.active.non_suspended.find_by("LOWER(email_address) = ?",
                                           params[:email_address].downcase)

  session[:otp_email_address] = user.email_address
  auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
  auth_token.deliver_later  # Background job sends email
  redirect_to new_auth_tokens_validations_path
end
```

#### Step 2: Validate OTP

**View:** 6-digit code entry form

**Code:**
```ruby
# smallbets-ce/app/controllers/auth_tokens/validations_controller.rb:9-20
def create
  auth_token = AuthToken.lookup(
    token: params[:token],
    email_address: session[:otp_email_address],
    code: params[:code]
  )

  auth_token.use!  # Mark as used, invalidate other tokens
  session.delete(:otp_email_address)
  start_new_session_for(auth_token.user)
  redirect_to post_authenticating_url
end
```

**AuthToken Model:**
```ruby
# smallbets-ce/app/models/auth_token.rb
class AuthToken < ApplicationRecord
  has_secure_token  # Random token for magic links

  belongs_to :user

  before_create :generate_code

  def self.lookup(token:, email_address:, code:)
    joins(:user)
      .where(used_at: nil)
      .where("expires_at > ?", Time.current)
      .where(users: { email_address: email_address })
      .find_by("auth_tokens.code = ? OR auth_tokens.token = ?", code, token)
  end

  def use!
    transaction do
      update!(used_at: Time.current)
      user.auth_tokens.where.not(id: id).update_all(used_at: Time.current)
    end
  end

  private
    def generate_code
      self.code = format("%06d", rand(100_000..999_999))
    end
end
```

**Flow:**
```
User visits /session/new
  ↓
Enter email only
  ↓
System creates AuthToken (6-digit code + random token)
  ↓
Email sent with:
  - 6-digit code
  - Magic link (click to sign in)
  ↓
User chooses:
  ├─ Option A: Enter 6-digit code manually
  │     ↓
  │     POST /auth_tokens/validations
  │
  └─ Option B: Click magic link in email
        ↓
        GET /auth_tokens/validate/:token
  ↓
Validate: not expired (15 min), not used, code/token match
  ↓
Valid? → Mark as used, create session, redirect
Invalid? → Show error
```

**Features:**
- ✅ No password to remember
- ✅ More secure (no password database breach risk)
- ✅ Email-based verification
- ✅ Two options (code or magic link)
- ✅ Rate limited (10 requests / 1 minute on both steps)
- ❌ Requires email access
- ❌ Two-step process
- ❌ 15-minute expiration window

**Database Schema:**
```sql
CREATE TABLE auth_tokens (
  id BIGINT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  token VARCHAR NOT NULL,        -- Random token for magic links
  code VARCHAR NOT NULL,          -- 6-digit numeric code
  expires_at TIMESTAMP NOT NULL,  -- 15 minutes from creation
  used_at TIMESTAMP,              -- Marks when OTP was used
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  UNIQUE(token),
  FOREIGN KEY(user_id) REFERENCES users(id)
);
```

---

## 3. Session Management

**STATUS: 🟢 NEARLY IDENTICAL**

Both systems use the exact same session management architecture.

### Shared Session Model

```ruby
# Both: app/models/session.rb (identical)
class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour

  has_secure_token  # Generates random 24-char token

  belongs_to :user

  before_create { self.last_active_at ||= Time.now }

  def self.start!(user_agent:, ip_address:)
    create! user_agent: user_agent, ip_address: ip_address
  end

  def resume(user_agent:, ip_address:)
    if last_active_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update! user_agent: user_agent, ip_address: ip_address, last_active_at: Time.now
    end
  end
end
```

### Shared Authentication Concern

```ruby
# Both: app/controllers/concerns/authentication.rb
def start_new_session_for(user)
  user.sessions.start!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
    authenticated_as session
  end
end

def authenticated_as(session)
  Current.user = session.user
  set_authenticated_by(:session)

  cookies.signed.permanent[:session_token] = {
    value: session.token,
    httponly: true,
    same_site: :lax
  }

  session[:user_id] = session.user.id
end
```

### Session Features

| Feature | Both Systems |
|---------|-------------|
| **Token Storage** | Signed, permanent, HTTP-only cookie |
| **Token Type** | `has_secure_token` (random 24-char string) |
| **Cookie Attributes** | `httponly: true, same_site: :lax, secure: production` |
| **Activity Tracking** | Last active updated every 1 hour (reduces DB writes) |
| **Expiration** | None (permanent until logout) |
| **Multi-Device** | ✅ Supported (multiple sessions per user) |
| **IP Logging** | ✅ Stored in sessions table |
| **User Agent** | ✅ Stored in sessions table |
| **Session Lookup** | By signed cookie token |
| **Session Destruction** | On logout or account deactivation |

### Database Schema

```sql
-- Both systems (identical)
CREATE TABLE sessions (
  id BIGINT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  token VARCHAR NOT NULL,
  ip_address VARCHAR,
  user_agent VARCHAR,
  last_active_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  UNIQUE(token),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### Minor Difference: Suspended User Check

**Once-Campfire:**
```ruby
# No suspension check - only active/inactive
def authenticated_as(session)
  Current.user = session.user
  # ... rest of method
end
```

**Smallbets-CE:**
```ruby
# Checks for suspension (Gumroad refunds)
def authenticated_as(session)
  return if session.user.suspended?  # ← Additional check
  Current.user = session.user
  # ... rest of method
end
```

---

## 4. User Model Differences

### Database Schema Comparison

| Field | Once-Campfire | Smallbets-CE | Purpose |
|-------|--------------|-------------|---------|
| `id` | ✅ | ✅ | Primary key |
| `name` | ✅ | ✅ | Display name |
| `email_address` | ✅ | ✅ | Unique identifier |
| `password_digest` | ✅ | ✅ | BCrypt hash (rarely used in smallbets-ce) |
| `role` | ✅ | ✅ | User role enum |
| `active` | ✅ | ✅ | Account activation status |
| `bot_token` | ✅ | ✅ | API authentication |
| `created_at` | ✅ | ✅ | Timestamp |
| `updated_at` | ✅ | ✅ | Timestamp |
| `order_id` | ❌ | ✅ | Gumroad order ID |
| `membership_started_at` | ❌ | ✅ | Purchase date from Gumroad |
| `last_authenticated_at` | ❌ | ✅ | Tracks first login |
| `suspended_at` | ❌ | ✅ | Refund suspension timestamp |

### User Role Enum

**Once-Campfire:**
```ruby
enum :role, %i[ member administrator bot ]
```

**Smallbets-CE:**
```ruby
enum :role, %i[ member administrator bot expert ]
#                                         ↑ New role for featured experts
```

### User States

**Once-Campfire:**
```ruby
# Two simple states
user.active == true  # Can sign in
user.active == false # Deactivated (cannot sign in)
```

**Smallbets-CE:**
```ruby
# Four effective states
1. Active + never authenticated      # Imported from Gumroad webhook, account unclaimed
2. Active + authenticated             # Normal user
3. Inactive                          # Deactivated account (user.deactivate called)
4. Active + suspended                # Gumroad refund (suspended_at present)
```

### Smallbets-CE Additional Methods

```ruby
# app/models/user.rb (smallbets-ce only)

def suspended?
  suspended_at.present?
end

def suspend!
  update!(suspended_at: Time.current)
end

def ensure_can_sign_in!
  update!(suspended_at: nil) if suspended?
end

def ever_authenticated?
  last_authenticated_at.present?
end

def imported_from_gumroad_and_unclaimed?
  order_id.present? && !ever_authenticated?
end

def self.from_gumroad_sale(params)
  # Complex Gumroad verification logic
  # Returns user or nil
end
```

### User Creation After-Hook

**Both systems (identical):**
```ruby
after_create_commit :grant_membership_to_open_rooms

private
  def grant_membership_to_open_rooms
    Membership.insert_all(
      Rooms::Open.pluck(:id).collect { |room_id|
        { room_id: room_id, user_id: id }
      }
    )
  end
```

New users automatically join all open rooms on account creation.

---

## 5. Authentication Mechanisms

### Available Methods Comparison

| Method | Once-Campfire | Smallbets-CE | Primary Use |
|--------|--------------|-------------|-------------|
| **Password** | ✅ Primary | ⚠️ Admin/legacy only | User sign-in |
| **OTP (6-digit code)** | ❌ | ✅ Primary | User sign-in |
| **Magic Link** | ❌ | ✅ Alternative | User sign-in (click link in email) |
| **Session Transfer** | ✅ | ✅ | Cross-device sign-in |
| **Bot API Key** | ✅ | ✅ | Bot integrations |
| **Session Cookie** | ✅ | ✅ | Stay logged in |

### Authentication Priority Flow

**Once-Campfire:**
```ruby
# app/controllers/concerns/authentication.rb
def require_authentication
  restore_authentication ||   # 1. Check session cookie
  bot_authentication ||        # 2. Check bot_key param
  request_authentication       # 3. Redirect to password login
end
```

**Smallbets-CE:**
```ruby
# app/controllers/concerns/authentication.rb
def require_authentication
  restore_authentication ||   # 1. Check session cookie (+ suspension check)
  bot_authentication ||        # 2. Check bot_key param
  request_authentication       # 3. Redirect to OTP request page
end
```

### Session Transfer (Identical in Both)

**Purpose:** Quick device-to-device authentication without password/OTP

**Controller:**
```ruby
# Both: app/controllers/sessions/transfers_controller.rb
class Sessions::TransfersController < ApplicationController
  allow_unauthenticated_access

  def show
    # Displays QR code / transfer link
  end

  def update
    if user = User.active.find_by_transfer_id(params[:id])
      start_new_session_for user
      redirect_to post_authenticating_url
    else
      head :bad_request
    end
  end
end
```

**User Model:**
```ruby
# Both: app/models/user/transferable.rb
module User::Transferable
  TRANSFER_LINK_EXPIRY_DURATION = 4.hours

  def transfer_id
    signed_id(purpose: :transfer, expires_in: TRANSFER_LINK_EXPIRY_DURATION)
  end

  def self.find_by_transfer_id(id)
    find_signed(id, purpose: :transfer)
  end
end
```

**Features:**
- Generates time-limited (4 hours) signed URL
- Encrypted user ID in URL
- Used for QR codes or direct links
- No password/OTP needed if you have the link
- Automatically expires after 4 hours

**Use Cases:**
- Switching from desktop to mobile
- Sharing access to trusted device
- IT support helping users log in

---

## 6. Security Features

### Comparison Matrix

| Security Feature | Once-Campfire | Smallbets-CE | Notes |
|-----------------|--------------|-------------|-------|
| **Password Hashing** | ✅ BCrypt | ✅ BCrypt | Rarely used in smallbets-ce |
| **Rate Limiting: Password** | ✅ 10/3min | ✅ 10/3min | Same implementation |
| **Rate Limiting: OTP Request** | N/A | ✅ 10/1min | Smallbets-CE only |
| **Rate Limiting: OTP Validation** | N/A | ✅ 10/1min | Smallbets-CE only |
| **Session Token Security** | ✅ Secure random | ✅ Secure random | `has_secure_token` |
| **Signed Cookies** | ✅ | ✅ | Tamper-proof |
| **HttpOnly Cookies** | ✅ | ✅ | XSS protection |
| **SameSite: Lax** | ✅ | ✅ | CSRF protection |
| **CSRF Protection** | ✅ | ✅ | Except bot_key auth |
| **Email Verification** | ❌ | ⚠️ Via OTP | OTP acts as email verification |
| **2FA/MFA** | ❌ | ❌ | Not implemented |
| **Password Reset** | ❌ | ❌ | Contact admin / Use OTP |
| **Account Lockout** | ❌ | ❌ | Rate limiting only |
| **Session Revocation UI** | ❌ | ❌ | No user interface to view/revoke sessions |
| **IP + User Agent Logging** | ✅ | ✅ | Stored in sessions table |
| **Token Expiration: Sessions** | ❌ Permanent | ❌ Permanent | Manual logout required |
| **Token Expiration: OTP** | N/A | ✅ 15 minutes | Auto-expires |
| **Token Expiration: Transfer** | ✅ 4 hours | ✅ 4 hours | Same |
| **Webhook Security** | N/A | ✅ Secret verification | Gumroad webhooks |
| **Bot Token Uniqueness** | ✅ DB constraint | ✅ DB constraint | Same |
| **Email Uniqueness** | ✅ DB constraint | ✅ DB constraint | Same |
| **Active User Check** | ✅ | ✅ | Deactivated users can't sign in |
| **Suspended User Check** | N/A | ✅ | Refunded users can't sign in |

### Security Strengths (Both)

1. **Secure Session Management**
   - Cryptographically random tokens
   - Signed cookies (tamper-proof)
   - HTTP-only (XSS protection)
   - SameSite:Lax (CSRF protection)

2. **Rate Limiting**
   - Prevents brute force attacks
   - Configurable per endpoint

3. **Activity Tracking**
   - IP address logging
   - User agent logging
   - Last active timestamp

4. **Bot Authentication Isolation**
   - Separate authentication method
   - No access to regular user routes

### Security Considerations

**Once-Campfire:**
- ⚠️ No password reset flow (admin contact required)
- ⚠️ Permanent sessions (no auto-timeout)
- ⚠️ No email verification
- ⚠️ No 2FA option

**Smallbets-CE:**
- ⚠️ 6-digit OTP (100K combinations, but rate limited)
- ⚠️ Permanent sessions (no auto-timeout)
- ⚠️ No 2FA option
- ⚠️ No session management UI
- ⚠️ OTP requires email access (potential lock-out if email compromised)

### Password Security Note

**Once-Campfire:** Password is primary auth method, must be strong and secure.

**Smallbets-CE:** Password field exists but rarely used:
- First-run admin setup only
- Legacy sign-in for admins who set password during first-run
- Most users never have a password (OTP only)

---

## 7. Gumroad Integration (Smallbets-CE Only)

**STATUS: 🔴 UNIQUE TO SMALLBETS-CE**

### Architecture Overview

```
Gumroad Sale
    ↓
Webhook → Background Job → Pre-import User
    ↓
User visits /join/{join_code}
    ↓
Gumroad API Verification → Claim Account
    ↓
User Authenticated

--- OR ---

Gumroad Refund
    ↓
Webhook → Suspend User
```

### Components

#### 1. Gumroad API Client

**File:** `app/models/gumroad_api.rb`

```ruby
class GumroadAPI
  BASE_URL = "https://api.gumroad.com/v2"

  def self.successful_membership_sale(email:)
    product_ids = ENV["GUMROAD_PRODUCT_IDS"].split(",")

    product_ids.each do |product_id|
      response = HTTParty.get(
        "#{BASE_URL}/products/#{product_id}/subscribers",
        query: {
          access_token: ENV["GUMROAD_ACCESS_TOKEN"],
          email: email
        }
      )

      next unless response.success?

      sale = response.parsed_response["subscriber"]

      # Exclude refunded, chargedback, or gift purchases
      next if ["refunded", "chargedback"].include?(sale["status"])
      next if sale["purchase_email"] != email  # Gift from someone else

      return sale if sale
    end

    nil  # No valid sale found
  end
end
```

**Environment Variables:**
- `GUMROAD_ON` - Enable/disable Gumroad checks ("true"/"false")
- `GUMROAD_ACCESS_TOKEN` - API access token
- `GUMROAD_PRODUCT_IDS` - Comma-separated product IDs

#### 2. Sale Webhook Handler

**Route:** `POST /webhooks/gumroad/users/:webhook_secret`

**File:** `app/controllers/webhooks/gumroad/users_controller.rb`

```ruby
class Webhooks::Gumroad::UsersController < Webhooks::Gumroad::BaseController
  def create
    Gumroad::ImportUserJob.perform_later(webhook_params)
    head :ok
  end

  private
    def webhook_params
      params.permit(:email, :full_name, :order_id, :created_at, :product_id)
    end
end
```

**Base Controller (Security):**
```ruby
# app/controllers/webhooks/gumroad/base_controller.rb
class Webhooks::Gumroad::BaseController < ApplicationController
  skip_before_action :verify_authenticity_token  # CSRF not applicable
  allow_unauthenticated_access

  before_action :verify_webhook_secret, :verify_product

  private
    def verify_webhook_secret
      unless params[:webhook_secret] == ENV["WEBHOOK_SECRET"]
        Rails.logger.warn "Unauthorized Gumroad webhook attempt"
        head :unauthorized
      end
    end

    def verify_product
      unless ENV["GUMROAD_PRODUCT_IDS"].split(",").include?(params[:product_id])
        head :ok  # Acknowledge but ignore (different product)
      end
    end
end
```

**Background Job:**
```ruby
# app/jobs/gumroad/import_user_job.rb
class Gumroad::ImportUserJob < ApplicationJob
  queue_as :default

  def perform(webhook_data)
    User.find_or_initialize_by(email_address: webhook_data[:email]).tap do |user|
      user.name = webhook_data[:full_name]
      user.order_id = webhook_data[:order_id]
      user.membership_started_at = webhook_data[:created_at]
      user.save!
    end
  rescue => e
    Rails.logger.error "Failed to import Gumroad user: #{e.message}"
    raise
  end
end
```

**Webhook Data Structure:**
```json
{
  "email": "user@example.com",
  "full_name": "John Doe",
  "order_id": "ABC123",
  "created_at": "2024-01-15T10:30:00Z",
  "product_id": "XYZ789",
  "webhook_secret": "your-secret-here"
}
```

#### 3. Refund Webhook Handler

**Route:** `POST /webhooks/gumroad/refunds/:webhook_secret`

**File:** `app/controllers/webhooks/gumroad/refunds_controller.rb`

```ruby
class Webhooks::Gumroad::RefundsController < Webhooks::Gumroad::BaseController
  def create
    user = User.find_by(order_id: params[:order_id])

    if user
      user.suspend!
      Rails.logger.info "Suspended user #{user.id} due to Gumroad refund"
    else
      Rails.logger.warn "Refund webhook for unknown order_id: #{params[:order_id]}"
    end

    head :ok
  end
end
```

**Suspension Logic:**
```ruby
# app/models/user.rb (smallbets-ce only)
def suspended?
  suspended_at.present?
end

def suspend!
  update!(suspended_at: Time.current)
end
```

**Effect of Suspension:**
```ruby
# app/controllers/concerns/authentication.rb
def authenticated_as(session)
  return if session.user.suspended?  # Prevents sign-in
  Current.user = session.user
  # ... rest of authentication
end
```

### User Creation Scenarios

**Smallbets-CE has 3 ways users are created:**

#### Scenario 1: Direct Sign-up (Traditional)
```
User purchases on Gumroad
  ↓
User visits /join/{join_code}
  ↓
Fills form (name, email, avatar)
  ↓
System calls GumroadAPI.successful_membership_sale(email)
  ↓
Sale found → Create user with order_id
  ↓
Auto-login
```

#### Scenario 2: Webhook Pre-import (Unique!)
```
User purchases on Gumroad
  ↓
Gumroad sends sale webhook
  ↓
Background job creates user:
  - name (from webhook)
  - email (from webhook)
  - order_id (from webhook)
  - membership_started_at (from webhook)
  - NO password_digest
  - NO last_authenticated_at (unclaimed)
  ↓
User visits /join/{join_code} later
  ↓
System finds existing user by email
  ↓
User "claims" account via OTP or auto-login
```

#### Scenario 3: First-run Admin (Same as Once-Campfire)
```
First visitor
  ↓
No Gumroad check
  ↓
Create admin account
```

### Gumroad Configuration

**Environment Variables:**
```bash
# Enable Gumroad integration
GUMROAD_ON=true

# API credentials
GUMROAD_ACCESS_TOKEN=your_token_here

# Product IDs (comma-separated for multiple products)
GUMROAD_PRODUCT_IDS=ABC123,XYZ789

# Webhook security
WEBHOOK_SECRET=your_webhook_secret_here
```

**Disabling Gumroad:**
```bash
# Fall back to simple registration (like Once-Campfire)
GUMROAD_ON=false
```

When `GUMROAD_ON=false`, the sign-up flow behaves like Once-Campfire (no payment verification).

---

## 8. Access Control

### Join Code System

**STATUS: 🟢 IDENTICAL**

Both systems use the exact same join code mechanism.

**Model:** `app/models/account/joinable.rb`

```ruby
module Account::Joinable
  extend ActiveSupport::Concern

  included do
    before_create { self.join_code = generate_join_code }
  end

  def reset_join_code
    update! join_code: generate_join_code
  end

  private
    def generate_join_code
      SecureRandom.alphanumeric(12).scan(/.{4}/).join("-")
      # Example: "AB12-CD34-EF56"
    end
end
```

**Features:**
- 12 alphanumeric characters
- Formatted as XXX-XXXX-XXXX
- Generated on account creation
- Admins can reset via UI
- Shared via URL, QR code, or web share API

**Management UI:**
```ruby
# Both: app/controllers/accounts/join_codes_controller.rb
class Accounts::JoinCodesController < ApplicationController
  before_action :ensure_can_administer

  def create
    Current.account.reset_join_code
    redirect_to edit_account_url
  end
end
```

**Route:** `POST /account/join_code`

### User Roles & Permissions

#### Role Definitions

**Once-Campfire:**
```ruby
enum :role, %i[ member administrator bot ]
```

**Smallbets-CE:**
```ruby
enum :role, %i[ member administrator bot expert ]
```

#### Authorization Logic (Identical)

```ruby
# Both: app/models/user/role.rb
def can_administer?(record = nil)
  administrator? ||
  self == record&.creator ||
  record&.new_record?
end
```

**Interpretation:**
- Administrators can administer anything
- Users can administer their own content
- Users can administer new (unsaved) records they're creating

#### Role Capabilities

| Capability | Member | Administrator | Bot | Expert |
|------------|--------|--------------|-----|--------|
| Post messages | ✅ | ✅ | ✅ | ✅ |
| Create rooms | ✅ | ✅ | ❌ | ✅ |
| Join open rooms | ✅ Auto | ✅ Auto | ❌ | ✅ Auto |
| Manage account settings | ❌ | ✅ | ❌ | ❌ |
| Reset join code | ❌ | ✅ | ❌ | ❌ |
| Create/manage bots | ❌ | ✅ | ❌ | ❌ |
| Change user roles | ❌ | ✅ | ❌ | ❌ |
| Deactivate users | ❌ | ✅ | ❌ | ❌ |
| Access normal routes | ✅ | ✅ | ❌ | ✅ |
| Use bot API | ❌ | ❌ | ✅ | ❌ |
| Featured on marketing page | ❌ | ❌ | ❌ | ✅* |

*Smallbets-CE only

### Room Access

**Three room types (identical in both):**

1. **Open Rooms**
   - All users automatically get membership on account creation
   - Visible to everyone
   - Anyone can post

2. **Closed Rooms**
   - Invitation-only
   - Creator must manually add members
   - Not visible to non-members

3. **Direct Messages**
   - Two-user conversations
   - Automatically created when messaging someone
   - Private to the two participants

**Auto-Join Logic:**
```ruby
# Both: app/models/user.rb
after_create_commit :grant_membership_to_open_rooms

private
  def grant_membership_to_open_rooms
    Membership.insert_all(
      Rooms::Open.pluck(:id).collect { |room_id|
        { room_id: room_id, user_id: id }
      }
    )
  end
```

### Public vs Private Access

**Single-Tenant Model (Both):**
- One Account per deployment
- One join_code per account
- No public access to any content
- All routes require authentication (except first-run, join, sign-in)

**How to add new users:**
1. Admin shares join URL: `/join/{join_code}`
2. New user registers via that URL
3. Auto-granted membership to open rooms
4. Can be added to closed rooms by admins/creators

**No anonymous viewing:**
- No public rooms
- No guest access
- No "view-only" mode
- Must have account to see anything

---

## 9. Critical Code Differences

### A. UsersController#create

**Once-Campfire (9 lines):**
```ruby
# once-campfire/app/controllers/users_controller.rb:8-16
def create
  @user = User.create!(user_params)
  start_new_session_for @user
  redirect_to root_url
rescue ActiveRecord::RecordNotUnique
  redirect_to new_session_url(email_address: user_params[:email_address])
end

private
  def user_params
    params.require(:user).permit(:name, :avatar, :email_address, :password)
  end
```

**Smallbets-CE (25 lines):**
```ruby
# smallbets-ce/app/controllers/users_controller.rb:14-38
def create
  @user = User.from_gumroad_sale(user_params)

  if @user.nil?
    redirect_to account_join_code_url, alert: "We couldn't find a sale..."
    return
  end

  deliver_webhooks_to_bots(@user, :created) if @user.previously_new_record?

  if @user.previously_new_record? || @user.imported_from_gumroad_and_unclaimed?
    start_new_session_for @user
    redirect_to root_url
  else
    start_otp_for @user
    redirect_to new_auth_tokens_validations_path
  end
end

private
  def start_otp_for(user)
    session[:otp_email_address] = user.email_address
    auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    auth_token.deliver_later
  end

  def user_params
    params.require(:user).permit(:name, :avatar, :email_address)
    # Note: no :password
  end
```

**Key Differences:**
1. Gumroad verification (`User.from_gumroad_sale`)
2. Handles pre-imported users (webhook scenario)
3. Redirects existing users to OTP flow
4. No password in permitted params
5. More complex branching logic

---

### B. SessionsController#create

**Once-Campfire:**
```ruby
# once-campfire/app/controllers/sessions_controller.rb:10-16
def create
  if user = User.active.authenticate_by(email_address: params[:email_address],
                                        password: params[:password])
    start_new_session_for user
    redirect_to post_authenticating_url
  else
    render_rejection :unauthorized
  end
end
```

**Smallbets-CE:**
```ruby
# smallbets-ce/app/controllers/sessions_controller.rb:10-18
# Same code but rarely used (admin legacy only)
# Most users use AuthTokensController instead
def create
  if user = User.active.authenticate_by(email_address: params[:email_address],
                                        password: params[:password])
    start_new_session_for user
    redirect_to post_authenticating_url
  else
    render_rejection :unauthorized
  end
end
```

**Smallbets-CE: Primary Auth (OTP):**
```ruby
# smallbets-ce/app/controllers/auth_tokens_controller.rb
class AuthTokensController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create

  def create
    user = User.active.non_suspended.find_by("LOWER(email_address) = ?", ...)
    session[:otp_email_address] = user.email_address

    auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
    auth_token.deliver_later
    redirect_to new_auth_tokens_validations_path
  end
end

# smallbets-ce/app/controllers/auth_tokens/validations_controller.rb
class AuthTokens::ValidationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create

  def create
    auth_token = AuthToken.lookup(
      token: params[:token],
      email_address: session[:otp_email_address],
      code: params[:code]
    )
    auth_token.use!
    start_new_session_for(auth_token.user)
    redirect_to post_authenticating_url
  end
end
```

---

### C. User Model: from_gumroad_sale

**Once-Campfire:**
```ruby
# Does not exist - users created directly
User.create!(name: "John", email_address: "john@example.com", password: "secret")
```

**Smallbets-CE:**
```ruby
# app/models/user.rb:78-89
def self.from_gumroad_sale(params)
  return new(params) unless ENV["GUMROAD_ON"] == "true"

  sale = GumroadAPI.successful_membership_sale(email: params[:email_address])
  return nil unless sale

  find_or_initialize_by(email_address: params[:email_address]).tap do |user|
    user.assign_attributes(params)
    user.order_id = sale["order_id"]
    user.membership_started_at = sale["created_at"]
    user.save!
  end
end
```

**Flow:**
1. If `GUMROAD_ON != "true"`: create user directly (like Once-Campfire)
2. Otherwise: call Gumroad API
3. If no sale found: return `nil` (sign-up fails)
4. If sale found: find existing user or create new one
5. Attach `order_id` and `membership_started_at` from Gumroad
6. Save and return user

---

### D. Authentication Entry Point

**Once-Campfire:**
```ruby
# app/controllers/concerns/authentication.rb:50-53
def request_authentication
  session[:return_to_after_authenticating] = request.url
  redirect_to new_session_url  # Password entry form
end
```

**Smallbets-CE:**
```ruby
# app/controllers/concerns/authentication.rb:50-53
# Identical code but different destination
def request_authentication
  session[:return_to_after_authenticating] = request.url
  redirect_to new_session_url  # OTP request form (email entry)
end
```

The route is the same, but the view is different:
- **Once-Campfire:** `sessions/new.html.erb` shows email + password fields
- **Smallbets-CE:** `sessions/new.html.erb` shows email only (redirects to OTP)

---

### E. Authenticated Session Check

**Once-Campfire:**
```ruby
# app/controllers/concerns/authentication.rb:63-86
def authenticated_as(session)
  Current.user = session.user
  set_authenticated_by(:session)

  cookies.signed.permanent[:session_token] = {
    value: session.token,
    httponly: true,
    same_site: :lax
  }

  session[:user_id] = session.user.id
end
```

**Smallbets-CE:**
```ruby
# app/controllers/concerns/authentication.rb:63-86
def authenticated_as(session)
  return if session.user.suspended?  # ← Additional check

  Current.user = session.user
  set_authenticated_by(:session)

  cookies.signed.permanent[:session_token] = {
    value: session.token,
    httponly: true,
    same_site: :lax
  }

  session[:user_id] = session.user.id
end
```

**Impact:** Suspended users (Gumroad refunds) cannot authenticate even with valid session.

---

## 10. Migration Path

### Shared Core Architecture (~70%)

Both codebases share:
- ✅ Session model (100% identical)
- ✅ Join code system (100% identical)
- ✅ Bot authentication (100% identical)
- ✅ Session transfer (100% identical)
- ✅ First-run setup (100% identical)
- ✅ User roles (95% identical - expert role added)
- ✅ Authorization logic (100% identical)
- ✅ Room membership (100% identical)
- ✅ Account model (100% identical)
- ✅ Current attributes (100% identical)

### Divergent Components (~30%)

**Unique to Once-Campfire:**
- Password-based authentication as primary method
- Simple user creation (no payment gate)
- Two-state user model (active/inactive)

**Unique to Smallbets-CE:**
- OTP authentication system (`AuthToken` model + controllers)
- Magic link alternative
- Gumroad integration (API client + webhooks)
- User suspension system
- Four-state user model (active/inactive/suspended/unclaimed)
- Expert role
- Marketing pages
- Additional user fields (`order_id`, `membership_started_at`, `last_authenticated_at`, `suspended_at`)

### Porting Features

#### From Once-Campfire → Smallbets-CE

**Missing Features:**
- Simple password auth (replaced by OTP)
- Direct user creation (replaced by Gumroad)

**To Add:**
1. Re-enable password field in sign-up form
2. Remove Gumroad verification
3. Simplify `UsersController#create`

**Difficulty:** Easy (removal of features)

---

#### From Smallbets-CE → Once-Campfire

**Missing Features:**
- OTP authentication system
- Magic link authentication
- Gumroad integration
- User suspension
- Expert role
- Marketing pages

**To Add:**
1. Create `auth_tokens` table + model
2. Add `AuthTokensController` + `AuthTokens::ValidationsController`
3. Add `suspended_at`, `order_id`, `membership_started_at`, `last_authenticated_at` to users
4. Create `GumroadAPI` model
5. Add Gumroad webhook controllers
6. Add background job for webhook processing
7. Update `User.from_gumroad_sale` method
8. Add suspension check to authentication flow
9. Update views (remove password, add OTP forms)
10. Add mailer for OTP delivery

**Difficulty:** Moderate (significant additions)

---

### Sync Strategy

**If maintaining both codebases:**

1. **Keep Once-Campfire as upstream**
   - Simple, clean implementation
   - No payment logic
   - Easier to understand and maintain

2. **Keep Smallbets-CE as downstream fork**
   - Periodically merge changes from Once-Campfire
   - Add Gumroad + OTP features on top
   - Maintain compatibility with core architecture

3. **Shared updates:**
   - Session management improvements
   - Security patches
   - Bot authentication changes
   - Room/message features
   - UI/UX improvements

4. **Fork-specific updates:**
   - Gumroad API changes (Smallbets-CE only)
   - OTP improvements (Smallbets-CE only)
   - Password auth improvements (Once-Campfire only)

---

## 11. Recommendations

### Use Once-Campfire When:

✅ Free community chat
✅ Internal team communication
✅ Self-hosted for friends/family
✅ No payment required
✅ Want simple password auth
✅ Need offline authentication
✅ Want minimal dependencies
✅ Don't want email requirements

**Example Use Cases:**
- Company internal chat
- Open-source project discussion
- Family group chat
- Gaming clan communication
- Hobbyist community

---

### Use Smallbets-CE When:

✅ Paid membership community
✅ Course/product with chat component
✅ Need payment gating
✅ Want passwordless auth
✅ Prefer email-based security
✅ Need refund handling
✅ Want user suspension capability
✅ Building SaaS product

**Example Use Cases:**
- Paid online courses
- Membership communities
- Premium Slack alternatives
- Product communities (post-purchase chat)
- Educational platforms

---

### Decision Matrix

| Priority | Choose Once-Campfire | Choose Smallbets-CE |
|----------|---------------------|-------------------|
| **Simplicity** | ✅ | ❌ |
| **No Payment** | ✅ | ⚠️ (can disable) |
| **Password Auth** | ✅ | ⚠️ (admin only) |
| **Offline Access** | ✅ | ❌ |
| **Email Verification** | ❌ | ✅ |
| **Payment Integration** | ❌ | ✅ |
| **Refund Handling** | ❌ | ✅ |
| **No Password Management** | ❌ | ✅ |
| **Security** | ✅ Good | ✅ Better |
| **User Experience** | ✅ Faster login | ⚠️ Two-step login |
| **Maintenance** | ✅ Simpler | ⚠️ More complex |

---

### Hybrid Approach

**Make Smallbets-CE work like Once-Campfire:**

Set environment variable:
```bash
GUMROAD_ON=false
```

This disables Gumroad verification, making sign-up work like Once-Campfire.

**Result:**
- OTP auth (no passwords)
- No payment gate
- Simple join code access
- Best of both worlds

---

## 12. File Reference

### Controllers

#### Shared (Identical or Nearly Identical)

| File | Status | Notes |
|------|--------|-------|
| `first_runs_controller.rb` | 🟢 Identical | First admin setup |
| `sessions/transfers_controller.rb` | 🟢 Identical | QR code / device transfer |
| `accounts/join_codes_controller.rb` | 🟢 Identical | Join code management |
| `qr_code_controller.rb` | 🟢 Identical | QR code generation |

#### Different

| File | Once-Campfire | Smallbets-CE | Difference |
|------|--------------|-------------|-----------|
| `users_controller.rb` | Password sign-up | Gumroad sign-up | Major |
| `sessions_controller.rb` | Primary password auth | Legacy password auth | Usage |
| `marketing_controller.rb` | ❌ Missing | ✅ Present | New |
| `auth_tokens_controller.rb` | ❌ Missing | ✅ Present | New |
| `auth_tokens/validations_controller.rb` | ❌ Missing | ✅ Present | New |
| `webhooks/gumroad/*` | ❌ Missing | ✅ Present | New |

---

### Models

#### Shared (Identical or Nearly Identical)

| File | Status | Notes |
|------|--------|-------|
| `session.rb` | 🟢 Identical | Session management |
| `first_run.rb` | 🟢 Identical | Initial setup |
| `account.rb` | 🟢 Identical | Account model |
| `current.rb` | 🟢 Identical | Thread-local attributes |

#### Different

| File | Once-Campfire | Smallbets-CE | Difference |
|------|--------------|-------------|-----------|
| `user.rb` | Simpler | More fields + methods | Moderate |
| `auth_token.rb` | ❌ Missing | ✅ Present | New |
| `gumroad_api.rb` | ❌ Missing | ✅ Present | New |
| `expert.rb` | ❌ Missing | ✅ Present | New |

---

### Concerns

#### Shared (Identical or Nearly Identical)

| File | Status | Notes |
|------|--------|-------|
| `authentication.rb` | 🟡 Nearly identical | Suspension check added in smallbets-ce |
| `authentication/session_lookup.rb` | 🟢 Identical | Cookie lookup |
| `authorization.rb` | 🟢 Identical | Admin checks |
| `user/bot.rb` | 🟢 Identical | Bot authentication |
| `user/transferable.rb` | 🟢 Identical | Device transfer |
| `account/joinable.rb` | 🟢 Identical | Join code generation |

#### Different

| File | Once-Campfire | Smallbets-CE | Difference |
|------|--------------|-------------|-----------|
| `user/role.rb` | 3 roles | 4 roles (expert added) | Minor |

---

### Migrations

#### Once-Campfire Only

```
db/migrate/
  20231215043540_create_initial_schema.rb
    - users table (basic fields)
  20240110071740_create_sessions.rb
  20240209110503_alter_users_add_bot_token.rb
```

#### Smallbets-CE Additional

```
db/migrate/
  ... (all Once-Campfire migrations) ...
  20240910115400_create_auth_tokens.rb
  20241123162248_add_order_id_to_users.rb
  20241124151653_add_suspended_at_to_users.rb
  20241226114337_add_last_authenticated_at_to_users.rb
```

---

### Views

#### Authentication Views

| File | Once-Campfire | Smallbets-CE | Purpose |
|------|--------------|-------------|---------|
| `first_runs/show.html.erb` | ✅ | ✅ | Initial setup form |
| `sessions/new.html.erb` | Password form | Email form (OTP) | Sign-in |
| `users/new.html.erb` | Password + email | Email only | Sign-up |
| `auth_tokens/validations/new.html.erb` | ❌ | ✅ | OTP code entry |
| `sessions/transfers/show.html.erb` | ✅ | ✅ | QR code display |

#### Marketing Views (Smallbets-CE Only)

```
smallbets-ce/app/views/marketing/
  show.html.erb          - Landing page
  _community_popup.html.erb
```

---

### Mailers

| File | Once-Campfire | Smallbets-CE | Purpose |
|------|--------------|-------------|---------|
| `auth_token_mailer.rb` | ❌ | ✅ | OTP email delivery |

---

### Jobs

| File | Once-Campfire | Smallbets-CE | Purpose |
|------|--------------|-------------|---------|
| `gumroad/import_user_job.rb` | ❌ | ✅ | Process sale webhooks |

---

### Routes

#### Once-Campfire

```ruby
# Authentication
resource :first_run
resource :session
get "join/:join_code", to: "users#new"
post "join/:join_code", to: "users#create"
resource :session do
  resources :transfers, only: %i[ show update ]
end

# Account management
resource :account do
  resource :join_code, only: :create
end
```

#### Smallbets-CE Additional

```ruby
# OTP authentication
resources :auth_tokens, only: %i[create]
namespace :auth_tokens do
  resource :validations, only: %i[new create]
end
get "auth_tokens/validate/:token", to: "auth_tokens/validations#create"

# Gumroad webhooks
namespace :webhooks, defaults: { format: :json } do
  namespace :gumroad do
    post "/refunds/:webhook_secret", to: "refunds#create"
    post "/users/:webhook_secret", to: "users#create"
  end
end

# Marketing
get "/join", to: "marketing#join"
get "/api/stats", to: "marketing#stats"
```

---

## Appendix: Environment Variables

### Once-Campfire

```bash
# Required
SECRET_KEY_BASE=your_secret_key_base_here

# Optional
SSL_DOMAIN=chat.example.com        # Enable Let's Encrypt SSL
DISABLE_SSL=true                   # Disable SSL (dev only)
VAPID_PUBLIC_KEY=your_public_key   # Web Push notifications
VAPID_PRIVATE_KEY=your_private_key
SENTRY_DSN=your_sentry_dsn         # Error tracking
COOKIE_DOMAIN=.example.com         # Multi-subdomain cookies
```

### Smallbets-CE Additional

```bash
# Gumroad Integration
GUMROAD_ON=true                    # Enable/disable Gumroad
GUMROAD_ACCESS_TOKEN=token_here    # API access token
GUMROAD_PRODUCT_IDS=ABC123,XYZ789  # Comma-separated product IDs
WEBHOOK_SECRET=your_webhook_secret # Webhook security

# Branding
APP_NAME=Your Community Name       # Marketing page title
SUPPORT_EMAIL=support@example.com  # Help contact

# Analytics (optional)
ANALYTICS_DOMAIN=your-app.com      # Plausible.io tracking
```

---

## Conclusion

**Once-Campfire** and **Smallbets-CE** share a strong architectural foundation but diverge significantly in authentication and payment handling:

- **Once-Campfire:** Simple, password-based, free access
- **Smallbets-CE:** Passwordless OTP, payment-gated, refund-aware

Both are production-ready systems with different use cases. Choose based on your business model and security preferences.

For most self-hosted scenarios, **Once-Campfire** provides simplicity.
For paid communities, **Smallbets-CE** provides necessary payment integration.

The ~70% shared codebase means updates to core functionality can flow from Once-Campfire → Smallbets-CE, maintaining compatibility while adding business-specific features.

---

**Document End**
