# Campfire-CE Modifications

This document tracks modifications made to the Campfire codebase specifically for Campfire-CE. These are additions beyond the Small Bets modifications documented in [`smallbets-mods.md`](smallbets-mods.md).


## Admin settings UI

Administrators can change authentication method and registration settings directly from the web interface at `/account/edit`. Switch between password and OTP auth, or toggle open registration on/off without modifying environment variables or redeploying.


## Email verification

New users must verify their email address before accessing the application. They receive an email with a verification link that expires after 2 days. Unverified users are redirected to a verification page until they confirm their email.


## Password reset

Members using password authentication can click "Forgot password?" to receive a password reset email. The reset link expires after 2 hours and can only be used once.
