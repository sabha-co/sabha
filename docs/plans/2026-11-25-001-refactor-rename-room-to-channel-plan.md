# Rename room to channel

Sabha calls its conversations "rooms"; Slack, Mattermost and Discord call them "channels", and so do the agents and outside apps that talk to Sabha. Nothing is in production yet, so this is the one cheap moment to switch. After launch it would mean an API version and a docs migration.

## Decisions

- **Rename everything**: UI, apps API, code, tables, routes, CSS, JS, docs. A UI-only rename (Zulip's choice when it renamed streams) leaves a permanent gap between what the code and the screens call a thing.
- **One STI family, as today**: `Channel` with `Channels::Open`, `Closed`, `Forum`, `Direct`, `Thread`, `Post`. Like Mattermost, a DM is a type of channel in code. In the UI: "channel", "private channel", "forum channel"; "direct message", "thread" and "post" keep their names.
- **Old links**: the migration rewrites saved `/rooms/…` links to `/channels/…`. No redirect route: nothing is launched, so there are no outside bookmarks to keep alive.
- **Action Cable already owns "Channel"**: `RoomChannel` (the base of presence and typing) becomes `ChannelScopedChannel`, matching the `ChannelScoped` controller concern, so nothing is called `ChannelChannel`. The other cable classes rename plainly (`ChannelStreamsChannel`, `ReadChannelsChannel`, `ChannelListChannel`, `UserUnreadChannelsChannel`).

## Size

About 9,900 mentions in 532 files and 194 paths. The rename is a rerunnable script, `script/rename_room_to_channel.rb`, so forks and open branches can apply the same rename to their own files.

## Steps

1. **Separate the words that already mean "channel"** (hand edits, own commit):
   - Stimulus controllers that hold a cable subscription in `this.channel` (presence, read rooms, typing) call it `this.subscription`.
   - The Slack importer names Slack's ids `slack_channel_id` / `slack_channel`, so they don't meet ours.
   - Comments that use "channel" for a notification delivery route (`membership/notifiable.rb`, `message.rb`, `account.rb`) are reworded.
   - `Room#roommate_to(user)` becomes `counterpart_to(user)`.
2. **Run the script** (own commit, nothing hand-edited):
   - `git mv` every tracked path containing "room", except `db/migrate`.
   - In file contents, a case-keeping substring swap (`room`→`channel`, `Room`→`Channel`, `ROOM`→`CHANNEL`), covering snake_case, camelCase, kebab-case and plurals. `RoomChannel`/`room_channel` map to `ChannelScopedChannel`/`channel_scoped_channel` first.
   - Skipped: existing migrations, `db/schema.rb`, schema caches, lockfiles, `vendor/`, binaries, the script itself. Protected words: headroom, broom, roomier, classrooms, "room to read".
   - Checks afterwards: no `ChannelChannel`/`channel_channel`/`channelChannel`; "room" survives only in protected words and old migrations; `bin/rails zeitwerk:check` passes.
3. **Data migration** (reversible, SQL that runs on SQLite and Postgres):
   - `rooms` → `channels`; `room_id` → `channel_id` on memberships and messages; `parent_room_id` → `parent_channel_id`.
   - Rename the custom-named indexes. Rebuild the unique thread index, whose `WHERE` names `Rooms::Thread`. Check the foreign keys from messages and from `solutions.post_id`.
   - `channels.type`: `Rooms::*` → `Channels::*`. Any polymorphic `*_type` column storing `Room` (Action Text, Active Storage, storage entries and totals).
   - System messages: `messages.event` `room_created`/`room_renamed` → `channel_*`, and their stored bodies ("created the room", "renamed the room from").
   - `accounts.settings` key `restrict_room_creation_to_administrators`.
   - `/rooms/` links inside Action Text bodies. Rooms aren't attachables, so no signed GlobalIDs need re-signing; the migration confirms it.
   - Then the tenanted workflow: hand-patch `db/schema.rb`, regenerate `db/schema_cache.yml` from the test database, `SAAS=true bin/rails db:migrate:primary`.
4. **Read the wording**: copy people see (views, mailers, PWA manifest, `public/llms.txt`), copy agents read (`skills/show.text.erb`, whose Slack comparison would otherwise read "Sabha channels ≈ Slack channels"), docs and test strings. `bin/rubocop -a` for alignment, `pnpm run lint:erb`.
5. **Verify**:
   - `bin/rails test`, `SAAS=true bin/rails test saas/test/`, and the system tests for the sidebar, channel page, forum, thread and DM.
   - Migrate a copy of a real dev database in both modes, then `down` and `up` again.
   - In the browser: create, rename and post in a channel; start a thread; open a forum post and a DM.
   - The apps API through the Developer Bench.
   - Open a PR to `sabha-co/sabha`.

## Outside the repo

The apps API's paths and keys change (`/api/bots/rooms`, `room_id`, `room_*` events and payloads). The clients that call it are updated separately, not in this change.

## Deploying

- Drain the job queue first: queued jobs carrying `gid://…/Room` or a `Room…Job` class won't resolve afterwards.
- Cache keys change, so caches warm again.
- The `last_room` cookie resets once; people land on their default channel one time.

## Forks and open branches

Merge this, then rerun the script over the files the merge didn't cover. Where a file conflicts, take this side and replay the other change through the script.
