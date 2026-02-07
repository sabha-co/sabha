# Sabha Modifications

This document tracks modifications made to the Campfire codebase specifically for Sabha. These are additions beyond the Small Bets modifications documented in [`smallbets-mods.md`](./smallbets-mods.md).


## Features

### Member management [#47](https://github.com/sabha-co/sabha/pull/47)

Administrators can manage all members from `/account/users` with:

- **Role management**: Promote/demote users between member, moderator, and administrator roles
- **Badges**: Assign badges (name + color) to highlight member roles or titles
- **Search**: Find members by name or email
- **Banned users**: View and unban previously banned users

Moderators have elevated permissions but cannot modify admin settings.


### Personal invite links [#25](https://github.com/sabha-co/sabha/pull/25)

Users can create personal invite links from their profile page:

- Personal links auto-expire after 7 days
- Admin setting to enable/disable user invite link creation
- Signup page shows inviter name and community stats


### Slack import [#22](https://github.com/sabha-co/sabha/pull/22)

Import your Slack workspace into Sabha:

- Import users, channels, messages, threads, and reactions from Slack export ZIP files
- Users are created as placeholders that can be claimed later
- Run via `bin/rails slack:import[path]` or `bin/rails slack:validate[path]`


### DiceBear avatars [#43](https://github.com/sabha-co/sabha/pull/43)

Users without profile photos get auto-generated avatars from DiceBear instead of plain initials:

- Users can shuffle to get a new random design
- Configure via `DICEBEAR_ENABLED`, `DICEBEAR_HOST`, `DICEBEAR_STYLE` environment variables


### User streaks [#49](https://github.com/sabha-co/sabha/pull/49)

Track consecutive days of posting with tiered streak icons displayed next to usernames.


### Theme switch [#15](https://github.com/sabha-co/sabha/pull/15)

Users can select Light, Dark, or Auto theme preference from their profile page. Theme applies before page render to avoid flash.


### AnyCable support [#20](https://github.com/sabha-co/sabha/pull/20)

Optional AnyCable integration for WebSocket scalability:

- Uses HTTP RPC mode (no gRPC required)
- 167x faster WebSocket connections in benchmarks
- Enable via `ANYCABLE_ENABLED` environment variable


### Solid Queue [#24](https://github.com/sabha-co/sabha/pull/24)

SQLite-backed background job processing (replaced Redis-backed Resque):

- Fork mode: Separate worker processes
- Async mode: Threads inside Puma (set `SOLID_QUEUE_IN_PUMA=true`)


### Authentication [#21](https://github.com/sabha-co/sabha/pull/21)

Two authentication methods are supported, configured via the `AUTH_METHOD` environment variable:

- **password**: Traditional email and password authentication
- **otp**: Passwordless login via 6-digit code sent to email

Only one method can be active at a time. Routes for the inactive method are blocked for security.


### Admin settings UI [#11](https://github.com/sabha-co/sabha/pull/11)

Administrators can change permission settings directly from the web interface at `/account/edit`:

- **Room creation restrictions**: Toggle whether only admins can create new rooms
- **Direct message restrictions**: Toggle whether only admins can initiate DMs
- **Invite link permissions**: Toggle whether members can create invite links

All settings take effect immediately without requiring environment variable changes or redeployment.


### User banning [#9](https://github.com/sabha-co/sabha/pull/9)

Administrators can ban problematic users from their profile page. When a user is banned:

- All IP addresses from their session history are blocked
- Their active sessions are terminated immediately
- All their messages are soft-deleted and removed from chat rooms
- Future requests from their IP addresses receive a 429 (Too Many Requests) response

Admins can also unban users, which restores their account and removes all IP blocks.


### Email verification

New users must verify their email address before accessing the application. They receive an email with a verification link that expires after 2 days. Unverified users are redirected to a verification page until they confirm their email.


### Password reset

Members using password authentication can click "Forgot password?" to receive a password reset email. The reset link expires after 2 hours and can only be used once.

### Email change Flow [#53](https://github.com/sabha-co/sabha/pull/53)

Users can change their email address from their profile page. The new email must be verified before replacing the current one. Notification emails are sent to both the old and new addresses for security.

### CSS mask-based icons [#45](https://github.com/sabha-co/sabha/pull/45)

Replaced image_tag calls with icon_tag helper using CSS masks for automatic color inheritance across light/dark themes.


### Bookmark indicator [#42](https://github.com/sabha-co/sabha/pull/42)

Display a small bookmark icon next to message timestamp when bookmarked, with real-time updates.


### AutoBootstrap for headless deployment [#16](https://github.com/sabha-co/sabha/pull/16)

Support headless deployment using `AUTO_BOOTSTRAP`, `ADMIN_AUTH_TOKEN`, `ADMIN_EMAIL` environment variables for automated setup.

This is a feature specific for sabha.co


## Fixes

### Soft deletion [#52](https://github.com/sabha-co/sabha/pull/52)

Comprehensive fixes to soft deletion behavior:

- User reactivation properly restores memberships
- Room merge moves all messages including inactive ones
- Ban properly deactivates memberships, auth tokens, and push subscriptions
- Deactivated users are blocked from authentication
- Added user reactivation UI for administrators


### Performance [#50](https://github.com/sabha-co/sabha/pull/50), [#13](https://github.com/sabha-co/sabha/pull/13)

- AJAX search for room member picker (handles 10k+ users)
- Cached member counts on signup page
- Fixed N+1 queries throughout the application
- Added composite database indexes for bookmarks, boosts, and messages


## Removals

The following features from the original codebase have been removed:

- **Gumroad integration** [#51](https://github.com/sabha-co/sabha/pull/51): Removed payment/licensing features
- **Marketing pages** [#44](https://github.com/sabha-co/sabha/pull/44): Unauthenticated users redirect directly to sign-in
- **Video library** [#14](https://github.com/sabha-co/sabha/pull/14): Removed video feature and Inertia.js/React infrastructure
- **Stats dashboard** [#49](https://github.com/sabha-co/sabha/pull/49): Replaced with simpler user streak tracking
- **Expert feature** [#3](https://github.com/sabha-co/sabha/pull/3): Removed expert role, expert directory, and message "answered" functionality
- **Room URL slugs** [#59](https://github.com/sabha-co/sabha/pull/59): Removed custom slug routing for rooms—users navigate via sidebar, not bookmarked URLs
