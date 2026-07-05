# Forums

A **forum** is a room type (`Rooms::Forum`) that presents its content as a gallery of titled posts instead of a chat stream — closer to a Discord forum channel or an old-school message board than to a live chat room. Like an Open room, it is a joinable sidebar room, but its posts do not ping every member.

## Anatomy of a post

A forum post is a first-class room: **`Rooms::Post`**, a sibling of `Rooms::Thread`. It belongs directly to its forum through `rooms.parent_room_id`, and its **opening body is simply its first message**; replies are the messages that follow. The post carries the title (stored in `name`), a permanent `slug`, and a Solved state (see below).

`Rooms::Forum#post!(title:, body:)` creates the post and its first message in one transaction, in the poster's `Current.user` context. The post keeps normal unread behavior for its own members; the forum does not — its `receive` is a no-op, so a new post never marks the forum unread or bumps chat counters. The gallery surfaces new posts by activity order instead of by an unread badge.

`Rooms::Post` and `Rooms::Thread` share two capabilities through concerns: participant listing (`Room::Participants` — the avatars on a card) and the cascade-deactivation lifecycle (`Room::Nested`). Everything else about a post — title, slug, Solved, forum-derived access — lives on `Rooms::Post`.

## Access & membership (no fan-out)

Access is **derived from the forum, not fanned out to every post**. Creating a post grants a membership to the author only; joining a forum creates **zero** post memberships. A post's `viewable_by?` delegates to its forum (`Rooms::Forum#viewable_by?`), so any forum member can read and reply to any post without holding a per-post row. This keeps `memberships` at roughly `participants`, not `members × posts`.

A member's post membership is created **lazily**, on engagement:

- **On reply** — `Message::Threadable#follow_post_by_creator` calls `Rooms::Post#follow!`, an idempotent, self-healing upsert (never downgrades an existing follower).
- **Via Follow** — the explicit opt-in for reply notifications without replying (see below).

Leaving a forum enqueues `ForumFollowCleanupJob`, which silences that one member's post follows (sets them invisible) so reply notifications stop; it never touches other members' follows.

## Where it renders

| Surface | Route | Renders |
|---------|-------|---------|
| Gallery | `/rooms/:id` — `RoomsController#show` → `render_forum_gallery` | `rooms/forums/gallery`, inside the normal room shell in place of the message stream |
| Post (panel) | `/rooms/posts/:id` — `Rooms::PostsController#show`, opened in the thread panel from a gallery card | `rooms/posts/show` (layout-less panel) |
| Post (permalink) | `/rooms/:forum_id?post=<slug>` — the gallery with the panel pre-opened | gallery + deep-linked panel |

A post has **no standalone page**. Its shareable link is a deep-link onto the forum gallery: `?post=<slug>` (plus an optional `&message_id=` to anchor a specific reply). `RoomsController#deep_linked_post` resolves the slug and the layout points the thread-panel frame at that post, so the panel opens over the gallery on load. A stale or non-viewable slug just yields the plain gallery.

## Composing

**New post** lives in the top nav (`rooms/show/nav`) and reveals an inline composer at the top of the gallery — no route change. Because the nav renders in a separate DOM subtree, the button reaches the gallery's `forum_compose` controller through a `forum-compose-opener` Stimulus outlet. The composer has a title field and a rich body that reuses the chat composer: the Trix editor with `@`-mention autocomplete, a rich-text toolbar toggle, and inline file attachments (`forum_body` controller). It submits to `Rooms::Forums::PostsController#create`, which calls `post!`.

## Filtering & sorting

The filter bar (`rooms/forums/_filter_bar`) offers:

- **Solved** — All / Open / Solved (`?solved=`), a `joins(:solution)` / `where.missing(:solution)` filter.
- **Sort** — Recent (`last_active_at`, default) / Newest (`created_at`) (`?sort=`).

Both are plain query params read by `Rooms::Forum#posts(solved:, sort:)`, which queries `Rooms::Post` on the denormalized `parent_room_id` FK so the filter + sort ride the `(parent_room_id, active, last_active_at)` composite index — no filesort.

## Solved state

Solved is modeled as a **record, not a column**: a `Solution` (`belongs_to :post, :user`) exists iff the post is solved, and it carries who marked it and when. `Rooms::Post#solved?` is `solution.present?`. Toggling goes through `Rooms::Forums::Posts::SolutionsController`:

- `create` → `solve!` ("Mark solved") — creates the `Solution`
- `destroy` → `reopen!` ("Reopen") — destroys it

`solve!`/`reopen!` broadcast `Rooms::Post#broadcast_content_change`, which live-refreshes the post header (title + Solved badge) and the gallery card everywhere they render.

## Following

Because access is forum-derived, a member is **not** automatically subscribed to a post's replies. **Follow** is the opt-in, modeled as state-as-records — the member's own membership on the post:

- **Follow** = membership `create` (`Rooms::Posts::MembershipsController#create` → `follow!`, involvement `everything`)
- **Unfollow** = membership `destroy`

The author and anyone who replies are followed implicitly (lazy membership). Changing an existing follow's level stays the ordinary `Rooms::InvolvementsController#update`.

## Slugs

Each post gets a permanent, URL-safe `slug` derived from its title on first save (`Rooms::Post#assign_slug`). The `rooms.slug` unique index is the hard guarantee against collisions; two same-titled posts that race are resolved by a retry in `post!` that picks the next numbered suffix.

## Post options menu

The `⋯` menu on a post header (`rooms/forums/_post_header`) offers:

| Item | Who | Action |
|------|-----|--------|
| Copy link | Anyone | Copies the post's permalink — the `?post=<slug>` gallery deep-link (`copy-to-clipboard`) |
| Follow / Unfollow | Any member | Create/destroy the viewer's own post membership |
| Edit | Admin / post author | Edit the title **inline** — `edit` swaps a form into the header's title turbo-frame (`dom_id(post, :title)`); `update` redirects so the frame swaps back |
| Mark solved / Reopen | Admin / post author | Toggle the Solved state |

## Live updates

The gallery subscribes to `turbo_stream_from @room, :posts` and `turbo_stream_from @membership`. Broadcasts keep it current:

- **New posts** prepend live — `Rooms::Post#broadcast_gallery_insertion` (an `after_create_commit`) streams the new card to the top of every member's open gallery.
- **Existing cards** refresh via replace broadcasts — a reply updates the card's reply count, activity, and participant avatars (`Message::Threadable#update_forum_gallery_card` → `Rooms::Post#broadcast_gallery_card`); a title or Solved change refreshes the card and the post header (`Rooms::Post#broadcast_content_change`).

The membership subscription is what lets the nav's involvement bell cycle its state.

Two accepted, self-correcting limits on the new-post stream: a viewer filtered to "Solved" briefly sees a new (unsolved) post, and a viewer sitting on the empty-state gallery (no list container yet) sees nothing until they navigate. Both resolve on the next load.

## Identity

Forum rooms use the `message-log` glyph across the sidebar indicator, the create-room form, the empty state, and the gated page (`room_type_indicator`).

## Key files

| Area | Files |
|------|-------|
| Models | `app/models/rooms/forum.rb`, `app/models/rooms/post.rb`, `app/models/solution.rb`, `app/models/room/participants.rb`, `app/models/room/nested.rb` |
| Controllers | `app/controllers/rooms/forums_controller.rb`, `rooms/forums/posts_controller.rb`, `rooms/forums/posts/solutions_controller.rb`, `rooms/posts_controller.rb`, `rooms/posts/memberships_controller.rb`, `concerns/forum_post_scoped.rb` |
| Jobs | `app/jobs/forum_follow_cleanup_job.rb` |
| Views | `app/views/rooms/forums/*`, `app/views/rooms/posts/*` |
| JS | `app/javascript/controllers/forum_compose_controller.js`, `forum_compose_opener_controller.js`, `forum_body_controller.js` |
| Styles | `app/assets/stylesheets/application/forum.css` |
| Routes | `config/routes.rb` — `resources :forums` (+ nested `posts` / `solution`), `resources :posts` (+ `membership`) |

## Not in v1

Post tags/categories were considered and cut to keep the first version simple — there is no taxonomy on posts. Posts have no standalone page — sharing is via the `?post=<slug>` gallery deep-link; a public, SEO-indexable post page is a possible future step but is not built.
