# Self-Hosted SSO

Sabha can use a parent application as a DiscourseConnect-compatible single sign-on provider. This is only for self-hosted installs. SaaS mode rejects `AUTH_METHOD=sso` at boot.

Use SSO when users should authenticate in another application and enter Sabha without local passwords or email codes.

## Before You Start

You need:

- A self-hosted Sabha deployment.
- A parent app that can authenticate users and implement a DiscourseConnect-compatible endpoint.
- A shared secret known only to Sabha and the parent app.
- Email addresses in the parent app that are verified, or a provider that sends `require_activation=true` for unverified addresses.

Generate a strong shared secret:

```bash
openssl rand -hex 64
```

## Configure Sabha

Set these environment variables:

```bash
AUTH_METHOD=sso
SSO_PROVIDER_URL=https://app.example.com/sso
SSO_SECRET=<shared-secret-from-openssl>

# Optional profile sync flags. Defaults are false.
SSO_OVERRIDES_NAME=false
SSO_OVERRIDES_AVATAR=false
```

Then restart Sabha so the environment changes take effect.

When SSO is enabled:

- Password sign-in redirects to SSO.
- OTP sign-in redirects to SSO.
- Magic-link token sign-in redirects to SSO.
- Password reset is disabled.
- Bot API bearer-token authentication continues to work.

## Provider Flow

When an unauthenticated user visits Sabha, Sabha redirects the browser to:

```text
SSO_PROVIDER_URL?sso=<base64-payload>&sig=<hmac-signature>
```

The payload contains:

| Field | Description |
| --- | --- |
| `nonce` | One-time value Sabha expects in the callback. |
| `return_sso_url` | Sabha callback URL, usually `https://chat.example.com/session/sso/callback`. |

The provider must:

1. Verify `sig` using HMAC-SHA256 over the exact `sso` parameter with `SSO_SECRET`.
2. Decode the base64 payload.
3. Authenticate the user in the parent app.
4. Build a response payload with at least `nonce`, `external_id`, and `email`.
5. Base64-encode the response payload.
6. Sign the encoded response payload with the same HMAC-SHA256 rule.
7. Redirect back to `return_sso_url?sso=<response-payload>&sig=<response-signature>`.

## Required Response Fields

| Field | Description |
| --- | --- |
| `nonce` | The nonce from Sabha's request. |
| `external_id` | Stable, immutable user id from the parent app. This is case-normalized by Sabha. |
| `email` | User email address. |

Optional fields:

| Field | Description |
| --- | --- |
| `name` | Used when creating users. Can update existing users when `SSO_OVERRIDES_NAME=true`. |
| `avatar_url` | Used when creating users. Can update existing users when `SSO_OVERRIDES_AVATAR=true`. |
| `require_activation` | Send `true` when the parent app has not verified the email. Sabha sends its own verification email and does not open a session until verification. |
| `failed` | Send `true` to reject sign-in without opening a session. |
| `logout` | Send `true` with a valid nonce to terminate the local Sabha session. |

Sabha ignores roles, groups, admin flags, usernames, 2FA fields, and custom fields in v1.

## Provider Example

This is the shape of a Rails provider action. Adapt the user lookup and sign-in checks to your app.

```ruby
require "base64"
require "openssl"
require "rack/utils"

class SsoController < ApplicationController
  SECRET = ENV.fetch("SABHA_SSO_SECRET")

  def show
    encoded_request = params.require(:sso)
    signature = params.require(:sig)

    unless secure_compare(signature, sign(encoded_request))
      head :forbidden
      return
    end

    request_payload = Rack::Utils.parse_query(Base64.decode64(encoded_request))
    user = current_user || authenticate_parent_app_user!

    response_payload = {
      nonce: request_payload.fetch("nonce"),
      external_id: user.id,
      email: user.email,
      name: user.name,
      avatar_url: user.avatar_url,
      require_activation: user.email_verified? ? "false" : "true"
    }

    encoded_response = Base64.strict_encode64(Rack::Utils.build_query(response_payload.compact))
    redirect_to "#{request_payload.fetch("return_sso_url")}?#{Rack::Utils.build_query(sso: encoded_response, sig: sign(encoded_response))}", allow_other_host: true
  end

  private
    def sign(payload)
      OpenSSL::HMAC.hexdigest("sha256", SECRET, payload)
    end

    def secure_compare(value, expected)
      value.present? &&
        value.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(value, expected)
    end
end
```

Use the same secret value for `SABHA_SSO_SECRET` in the parent app and `SSO_SECRET` in Sabha.

## User Matching

Sabha resolves SSO users in this order:

1. Existing `SingleSignOnRecord.external_id`.
2. Existing active user by email, only when `require_activation` is not true and the user does not already have an SSO record.
3. New user provisioning.

This lets existing self-hosted installs move to SSO without forcing every user to recreate an account.

## Email Claiming Risk

Email matching trusts the parent app's email verification.

If the parent app lets someone use `alice@example.com` without verifying ownership, that user could claim the existing Sabha account for `alice@example.com`.

Mitigations:

- The parent app should verify email ownership before sending `require_activation=false`.
- Send `require_activation=true` for any unverified email.
- For sensitive installs, pre-seed `SingleSignOnRecord` mappings before enabling SSO instead of relying on first-login email matching.
- Do not let users freely change the parent-app email that maps to an existing `external_id` unless the new email is verified.

## Enabling SSO On An Existing Install

Recommended rollout:

1. Confirm the parent app verifies email addresses.
2. Add the provider endpoint in the parent app.
3. Configure `SSO_PROVIDER_URL` and `SSO_SECRET` in Sabha.
4. Test the provider with a non-admin account in staging.
5. Decide whether to pre-seed SSO records for admins and other sensitive accounts.
6. Enable `AUTH_METHOD=sso`.
7. Restart Sabha.
8. Test sign-in, invite links, logout, and bot API access.

Existing browser sessions may continue until they expire or users sign out. If you need a hard cutover, invalidate existing `Session` rows as part of the rollout.

## Invite Links

Invite links continue to work in SSO mode:

1. User opens `/join/:join_code`.
2. Sabha validates the join code.
3. Sabha sends the user through SSO.
4. After a successful callback, Sabha redeems the join code before opening the session for a newly provisioned user.

If the invite expires during the SSO round trip, new-user signup is rejected.

## Rollback

To leave SSO mode:

1. Set `AUTH_METHOD=password` or `AUTH_METHOD=otp`.
2. Restart Sabha.
3. Confirm local sign-in works.

SSO identity records remain in the database. They are harmless when `AUTH_METHOD` is not `sso`.

Users who were provisioned by SSO may not know a local password. If rolling back to password auth, use password reset or admin support procedures to help those users regain access.

## Troubleshooting

### "Single sign-on is not configured"

Check:

- `AUTH_METHOD=sso`
- `SSO_PROVIDER_URL` is set.
- `SSO_SECRET` is set.
- The app was restarted after env changes.

### Callback returns 403

Common causes:

- Provider signed a decoded payload instead of the exact base64 `sso` value.
- Provider used a different secret.
- Provider changed whitespace or encoding before signing.
- The nonce expired.
- The callback was opened in a different browser session from the one that started SSO.
- The same callback URL was reused after a successful sign-in.

### User sees verification email instead of a session

The provider sent `require_activation=true`. Sabha sent its own verification email and will not open a session until the user verifies that email.

### Existing account cannot sign in

Check whether the email is already linked to a different SSO `external_id`. Sabha rejects ambiguous claims to avoid account takeover.

### Invite link fails after SSO

The join code may have expired or reached its usage limit during the SSO round trip. Ask the workspace admin for a new invite link.
