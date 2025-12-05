# Campfire-CE Modifications

This document tracks modifications made to the Campfire codebase specifically for Campfire-CE. These are additions beyond the Small Bets modifications documented in [`smallbets-mods.md`](smallbets-mods.md).


## Admin settings UI [#11](https://github.com/superforumio/campfire-ce/pull/11)

Administrators can change authentication method and permission settings directly from the web interface at `/account/edit`. The admin settings panel includes:

- **Authentication method**: Switch between password (email + password) and OTP (passwordless email code) authentication
- **Room creation restrictions**: Toggle whether only admins can create new rooms
- **Direct message restrictions**: Toggle whether only admins can initiate DMs

All settings take effect immediately without requiring environment variable changes or redeployment.


## User banning [#9](https://github.com/superforumio/campfire-ce/pull/9)

Administrators can ban problematic users from their profile page. When a user is banned:

- All IP addresses from their session history are blocked
- Their active sessions are terminated immediately
- All their messages are soft-deleted and removed from chat rooms
- Future requests from their IP addresses receive a 429 (Too Many Requests) response

Admins can also unban users, which restores their account and removes all IP blocks.


## Email verification

New users must verify their email address before accessing the application. They receive an email with a verification link that expires after 2 days. Unverified users are redirected to a verification page until they confirm their email.


## Password reset

Members using password authentication can click "Forgot password?" to receive a password reset email. The reset link expires after 2 hours and can only be used once.
