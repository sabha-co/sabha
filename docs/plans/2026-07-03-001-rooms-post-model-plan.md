# Plan: Forum posts as first-class `Rooms::Post` rooms

**Status:** proposed · **Date:** 2026-07-03 · **Branch:** `feat/forum-rooms` (pre-merge, local-only)

> **No data migration.** `Rooms::Post` reuses columns that already exist on `rooms` — `name` (title), `slug`, `parent_room_id`, `cascade_deactivated` — and `parent_message_id` stays null for posts. The only schema change is for Solved (D6): drop the branch-local `solved_at` column and add a `solutions` table. Because the whole forum feature is unmerged and local-only, none of this touches production data — existing local posts are **discarded and reseeded**, not migrated.

## Goal

Replace the current forum-post model — an **opening `Message` in the forum + a `Rooms::Thread` hung off it** — with a single **`Rooms::Post`** room that belongs directly to its forum, whose **OP is just its first message**. This removes the message→thread indirection that forced the `parent_room_id` denormalization, the orphaned opening message, the P2 filesort, and the pile of `if forum_post?` guards inside `Rooms::Thread`.

Visual rationale: the architecture explainer (Today vs Proposed). This plan is the execution of the "Proposed" column.

## What stays / what changes

- **Stays:** forums are joinable sidebar rooms (`Rooms::Forum`); the gallery, filter bar, Solved toggle, `/f/:slug` canonical page, slugs, live card broadcasts — all keep their current behavior and routes.
- **Changes:** a post is a `Rooms::Post` (not a `Rooms::Thread`); it has no `parent_message`; its body is message #1; `Rooms::Thread` reverts to meaning only "a chat thread off a message." Post access derives from forum membership — memberships are lazy, not fanned out to every member (D2).

## Prior art — Fizzy (verified against source)

Both load-bearing decisions mirror how Fizzy models boards + cards — checked in the actual repo, not the style guide. Read **forum = board, post = card**:

- **Access is a container record, derived downward — no per-item access row.** `Access belongs_to :board, :user` is one row *per board*, and a card delegates access to it: `delegate :accessible_to?, to: :board` (`card/accessible.rb`). Per-card rows exist only for *engagement*: `Watch` is `first_or_create`d on demand and the creator is auto-subscribed (`after_create :subscribe_creator`, `card/watchable.rb`); read state is derived from notifications, not a fanned-out read row (`card/readable.rb`). Even Fizzy's one fan-out (`grant_access_to_everyone` on an all-access board) is board-level and one-off, never per-card × member. → this **is** D2.
- **Binary state is a record carrying a `user`, not a timestamp.** `Closure`, `Card::Goldness`, `Card::NotNow` are all records with `belongs_to :user`; `closed?` = `closure.present?`, `closed_by`/`closed_at` derived, `joins(:closure)` / `where.missing(:closure)` scopes (`closure.rb`, `card/closeable.rb`). None point at another record — there is no "which comment closed it." → informs D6.
- **One intentional divergence.** Fizzy puts the OP *on* the item (`Card has_rich_text :description`, `card.rb:13`) with replies as separate `Comment` records — the question is structurally distinct from the answers. Sabha keeps the OP as the post's first `Message` (a room's content is its message stream, not a body field), so the OP has **no structural marker** — `forum_op?` identifies it as the earliest message, kept deterministic. Accepted for Sabha-consistency; the cost is that OP identity relies on ordering rather than structure.

## Decisions to lock before coding

| # | Decision | Recommendation |
|---|----------|----------------|
| D1 | `Rooms::Post` inheritance | **`Rooms::Post < Room`**, sibling of `Rooms::Thread`. Share the common behavior via **capability-named, single-purpose concerns** — not one grab-bag: a **`Room::Participants`** concern (`participant_creators` + preload) kept separate from the cascade-deactivation lifecycle (a small `Room::Nested`-style concern, or leave it on the subclasses if too thin to extract). Avoid a catch-all `Participable`. (`Post < Thread` is rejected — it would need `parent_message` optional and drag thread semantics along.) |
| D2 | Post access / memberships | **Derive access from the forum; make post memberships lazy.** `viewable_by?` is defined once on the forum and **delegated** from the post (`delegate :viewable_by?, to: :parent_room`), not a per-post row — so `post!` stops fanning membership out to every forum member. A post membership is created only when a user engages: implicitly on reply, or explicitly via **Follow**. This collapses `memberships` from ~`members × posts` toward ~`participants`; and because posts leave `has_many :threads, through: :messages`, the O(posts)-per-join cascade in `grant_to` stops touching posts for free. No unread behavior is lost — today's fanned-out rows are `involvement: "invisible"` and never drive a badge (unread only touches `visible` memberships), and forums show no per-post unread badge at all (`Rooms::Forum#receive` is a no-op). Leaving a forum revokes post access for free (nothing to clean); a cleanup **job** drops the member's opt-in post Follows, mirroring Fizzy's `clean_inaccessible_data`. |
| D3 | In-app panel | Add **`posts#show`** rendering the post in the side panel (mirrors today's thread-panel view). Gallery cards link here instead of `rooms_thread_path`. `/f/:slug` stays the standalone page. |
| D4 | Deleting a post | Post deletion = **deactivate the `Rooms::Post`** (like deleting a thread today). Deleting the OP *message* is ordinary message behavior; it no longer implies deleting the post. The `deactivate_forum_post_when_opening_message_removed` callback is removed. |
| D5 | `parent_room_id` scope | Keep the column on `rooms` for **both** subtypes: `Rooms::Post.parent_room` = its forum (the real FK, auto-set via `has_many :posts`); chat `Rooms::Thread.parent_room` = `parent_message.room` (still denormalized via `assign_parent_room`). One column, one meaning: "the container." |
| D6 | Solved as a record | **Adopt a `Solution` record; drop `solved_at`.** `solved_at` was added in this branch and never reached production, so removing the column is free — no production data, and local posts are reseeded anyway. `Solution belongs_to :post, :user`: `solved?` = `solution.present?`, `solve!`/`reopen!` create/destroy it, `solved_by`/`solved_at` derive from the record (so views calling `post.solved_at` keep working). Scopes become `joins(:solution)` / `where.missing(:solution)`, and `solved_by` / `recently_solved` fall out free — the exact shape of Fizzy's `Closure`/`Goldness`. **Not** accepted-answer UX (no pointer to the answering message) — Fizzy never points a state record at another record. Cost: one schema migration (drop `solved_at`, create `solutions`), no data migration. |

## Phases

The whole thing ships on one branch; phases are for review order. There is no schema or data migration (see the note above) — the only "data" step is wiping and reseeding local dev.

### Phase 1 — Introduce `Rooms::Post` (parallel, unused)

- Extract shared behavior into **cohesive, capability-named concerns**, included by both `Rooms::Thread` and `Rooms::Post` — two separate axes, don't merge them into one `Participable`:
  - **Participant listing** (display): `participant_creators` + `preload_participant_creators` → **`Room::Participants`**.
  - **Cascade lifecycle**: `deactivate(cascade:)` / `reactivate` / `cascade_deactivated` → a small nesting concern (e.g. `Room::Nested`), or keep on the subclasses if it's too thin to justify a file (CLAUDE.md: don't over-extract). `assign_parent_room` stays per-subclass (Thread from `parent_message`, Post via the forum FK).
- **Migration (D6):** drop `rooms.solved_at`; create a `solutions` table (`post_id` → `rooms`, `user_id`, timestamps; unique index on `post_id`). New model `app/models/solution.rb` (`belongs_to :post, class_name: "Rooms::Post", touch: true`; `belongs_to :user`), mirroring `Closure`.
- New `app/models/rooms/post.rb` (`Rooms::Post < Room`): `title`/`title=` (→ `name`), `slug` (`assign_forum_post_slug`), `has_one :solution, dependent: :destroy` with `solved?` (`solution.present?`), `solve!`/`reopen!` (create/destroy the record), `solved_by`/`solved_at` derived from it; `delegate :viewable_by?, to: :parent_room` (**the forum defines it** — see D2), `default_involvement` (author → `everything`), `broadcast_gallery_card` + `broadcast_content_change`, the `solved` (`joins(:solution)`) / `unsolved` (`where.missing(:solution)`) / `recently_active` / `reverse_chronologically` scopes, `belongs_to :parent_room` = the forum.
- `content_changed?` now tracks only `saved_change_to_name?` (title); the Solved broadcast fires from `solve!`/`reopen!` (or a `Solution` `after_commit`), since the state no longer lives in a `rooms` column.
- `Rooms::Forum`: `has_many :posts, -> { active }, class_name: "Rooms::Post", foreign_key: :parent_room_id`; and a `viewable_by?(user)` (membership check) that `Rooms::Post` delegates to — define access once on the container, Fizzy-style (`Card delegate :accessible_to?, to: :board`).
- Unit tests: `test/models/rooms/post_test.rb` (create, slug, solve/reopen creates+destroys a `Solution`, `solved_by`, viewable_by, broadcasts).

### Phase 2 — Switch creation + queries + access model (D2)

- `Rooms::Forum#post!`: create a `Rooms::Post` and grant a membership to **the author only** (`involvement: "everything"`), then `post.messages.create!(body:, creator: Current.user)` as message #1. **No fan-out to forum members.** Keep the slug-race retry.
- **Access is defined on the forum, delegated by the post** (Fizzy: `Comment delegate :accessible_to?, to: :card` → `Card … to: :board`): `Rooms::Forum#viewable_by?(user)` = `memberships.active.exists?(user_id: user.id)`; `Rooms::Post` does `delegate :viewable_by?, to: :parent_room`. Not a per-post row.
- **Lazy membership on reply (callback):** mirror Fizzy's `Comment#watch_card_by_creator` — an `after_create_commit` on a post's messages that `find_or_create`s the creator's post membership (`involvement: "everything"`, idempotent — never downgrade an existing follower), not ad-hoc controller code. Their own read/unread then works normally.
- **`grant_to` cascade:** no code change — once posts leave `has_many :threads, through: :messages`, a forum's `threads` is empty, so joining a forum no longer fans membership into posts. Chat rooms keep the cascade for their (bounded) chat threads.
- **Cleanup on forum-leave:** access revokes for free (no per-post rows), but drop the leaver's opt-in post Follows so they stop getting reply notifications. Hook `Membership#leave!` / `Room#remove_member!` for forums; touches only that member's followed posts, not all members. Run it as a **job** (Fizzy's `clean_inaccessible_data` shape), since it can span many posts.
- `Rooms::Forum#posts(solved:, sort:)`: query `posts` (association) instead of `Rooms::Thread.where(parent_room_id:)`.
- Controllers:
  - `ForumPostScoped#set_forum/#set_post` → `@forum.posts.find_by(...)`.
  - `Rooms::Forums::PostsController` → operate on `Rooms::Post`; `…::SolutionsController` `create`/`destroy` now back a real `Solution` record (`post.solve!` / `post.reopen!`).
  - `ForumPostsController` (`/f/:slug`) → `Rooms::Post.active.find_by(slug:)`; gate on the forum-derived `viewable_by?`; render the post's own messages (no `parent_message` prepend).
  - `RoomsController#render_forum_gallery` → `@room.posts(...)`, `Rooms::Post.preload_participant_creators`.

### Phase 3 — Views + panel + Follow (D3, D2)

- `app/views/rooms/posts/show.html.erb` — the in-app panel (header + message list + reply composer), split cleanly from `rooms/threads/show` (which reverts to chat-only, dropping its `if @room.forum_post?` branch).
- `_post_card` link → `posts#show` (panel) instead of `rooms_thread_path`.
- `_post_header`, `_post_header_state`, `_solved_toggle` → paths keyed to `Rooms::Post`.
- **Follow control (D2)** — forum members are no longer auto-members of every post, so getting replies without replying needs an explicit opt-in. Model it as **state-as-records — no `follow`/`unfollow` verb**:
  - **Follow = membership `create`** on the post (`involvement: "everything"`); **Unfollow = membership `destroy`**. Because access is forum-derived, a member has no post membership to begin with — so Follow *creates* the row (this is why it's a create, not an involvement `update`).
  - **Changing level once you're already a member** (e.g. a replier dialing everything → mentions) stays the existing `Rooms::InvolvementsController#update`.
  - Reuse the membership + involvement vocabulary rather than inventing a controller — but note `Rooms::MembershipsController#create` today is heavier "join a sidebar room" semantics (announce/welcome, Open/Forum only), so this is a RESTful membership create/destroy **scoped to the post**, not a literal drop-in of that action.
  - Author and repliers are followed implicitly (lazy membership on reply, per Phase 2).
- `forum_posts/show` (`/f/:slug`) → renders the post's messages with the OP inline as message #1 (remove the "prepend parent message from another room" logic).
- `messages_helper#forum_op?` → OP = the post's **earliest message** (deterministic `order(:created_at, :id).first`), not a "same author" guess. The OP has no structural marker (unlike Fizzy, where it's the card's own `description`), so keep its identification deterministic. Simplify.

### Phase 4 — Message-layer simplification

- `Message#forum_post` → `room if room.is_a?(Rooms::Post)` (drop the opening-message branch).
- `Message::Threadable#update_forum_gallery_card` → `room.broadcast_gallery_card if room.is_a?(Rooms::Post)`.
- **Remove** `deactivate_forum_post_when_opening_message_removed` (D4).
- **Remove** the P2a forum guards now dead (a forum never receives messages): `Rooms::Forum#receive` no-op, `touch_room_activity`'s `unless room.forum?`, `post_system_message`'s `return if forum?`. Verify each is truly unreachable for forums before deleting.

### Phase 5 — Cleanup + fresh seed data

- **No migration.** Discard local forum data (`Rooms::Forum` + its thread-shaped posts) — e.g. `Room.forums.destroy_all` in a console, or a fresh `bin/rails db:reset`.
- Optional but recommended: add forum seeding to `lib/tasks/generate.rake` (there is none today) — create a `Rooms::Forum` and a few posts via `post!` — so local dev has realistic forum data after reseeding. Since `post!` now yields `Rooms::Post`, the seed data is correct by construction.
- Remove the forum-specific guards from `Rooms::Thread` (`forum_post?`, `validates :name … if: :forum_post?`, `assign_forum_post_slug`, solved/title/broadcast members) — now on `Rooms::Post`.
- Reconsider `Room#threads`: with posts separated, `has_many :threads, through: :messages` reverts to chat-only meaning. Keep as-is unless the member-cascade wants the direct FK.
- Update `docs/features/FORUMS.md` (anatomy, key files, "not a new model" → "a `Rooms::Post` room").

### Phase 6 — Verification

- Update/port all forum tests: `forum_test`, `posts_controller_test`, `solutions_controller_test`, `forum_posts_controller_test`, the forum bits of `thread_test`, `messages_helper_test`.
- New: `post_test` (create, slug, solve/reopen via `Solution` create/destroy, `solved_by`, `viewable_by?` via forum membership, broadcasts).
- New access-model tests (the scale contract): `post!` creates **one** membership (the author), not one per forum member; a forum member views a post **without** a post membership; a non-forum-member is denied; replying creates a lazy membership (and doesn't downgrade an existing follower); Follow/Unfollow creates/removes a membership; joining a forum with existing posts creates **zero** post memberships; leaving a forum destroys that member's post Follows but not other members'.
- Run **both** suites (`bin/rails test` and `SAAS=true` per the SaaS env note) + `EXPLAIN` the gallery query — confirm the `where.missing(:solution)` anti-join still drives from the `(parent_room_id, active, last_active_at)` index with no filesort (order stays on `rooms`).

## Risks & watch-items

- **Concern extraction** — the main risk now. Moving `participant_creators` and the cascade lifecycle out of `Rooms::Thread` into shared concerns must not change chat-thread behavior. Land Phase 1 with chat-thread tests green before switching anything.
- **Panel UX (D3)** — cards currently open the *thread panel*; make sure the new `posts#show` panel keeps the same open/close/deeplink behavior (turbo-frame `thread_panel_frame` or a renamed equivalent).
- **Dead-guard removal (Phase 4)** — before deleting `receive` / `touch_room_activity` / `post_system_message` forum branches, confirm each is genuinely unreachable now that a forum never owns messages.
- **SaaS** — no migration, but still shared models; run the SaaS suite and, if seeding, reseed a workspace to eyeball a forum.
- **Access-derivation correctness (D2)** — now *in* scope and load-bearing. Audit every place that assumed "a post membership exists for all forum members": `viewable_by?` (now forum-derived), `bot_memberships_for_events` (bots must derive post eligibility from forum membership, or be followed lazily), any gallery/panel gate, and the canonical-page guard. A missed spot = a member wrongly locked out of a post they can see, or a bot silently not firing.
- **Follow UX (D2)** — "everyone is already a member" stops being true, so Follow is the only way to get reply notifications without replying. Make it discoverable, and ensure author/repliers are followed implicitly (no dead-end where a post author stops hearing about replies to their own post).
- **Association cleanup (D6)** — per CLAUDE.md, adding `has_one :solution` means auditing `Room#destroy_all_associated_records` and the `deactivate`/`reactivate` paths: destroying a forum must cascade to its posts and their `solutions` (`dependent: :destroy` on the post covers hard-destroy; a soft-deactivated post can keep its solution).

## Out of scope

- Changing the *unread mechanism itself* — it still keys off `visible` memberships (`unread_at`, notification counts). D2 changes *access* (who has a membership at all), not how unread is computed.
- The `threads`-through-messages consolidation (superseded — posts no longer use `threads`).
- Public/SEO `/f/:slug` and post tags (already "not in v1").

## Follow-ups

- **Chat-thread membership fan-out.** `Rooms::Thread` keeps today's behavior: creating a chat thread grants a membership to every active member of the parent room (`rooms/threads_controller.rb` passes `users: parent_room.users`), and `grant_to` cascades room joins into every thread (`room.rb:13`) — mostly `involvement: "invisible"`, the same shape D2 removes for posts. We fix it **only for posts** here: for posts it stops for free once they leave `has_many :threads, through: :messages`, whereas rewriting it for threads would touch the live, well-tested thread unread/involvement/notification paths. It's the same fan-out *in kind*, just bounded in practice — a room has few threads, a forum accumulates posts unboundedly — so a very large, very active room still hits the wall eventually. **Eventual fix:** apply the D2 model to `Rooms::Thread` too — derive thread access from the parent room and lazy-create thread membership (mirrors Fizzy: a card's access delegates to its board, `Watch` is lazy). Deliberately deferred, not overlooked.
