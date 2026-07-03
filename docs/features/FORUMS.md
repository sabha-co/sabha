# Forums

A **forum** is a room type (`Rooms::Forum`) that presents its content as a gallery of titled posts instead of a chat stream — closer to a Discord forum channel or an old-school message board than to a live chat room. Like an Open room, it is a joinable sidebar room, but its posts do not ping every member.

## Anatomy of a post

A forum post is not a new model. It reuses the existing thread stack:

- an **opening `Message`** in the forum (holds the post body), plus
- a **`Rooms::Thread`** spawned on that message — this *is* the post. It carries the title (stored in `name`), a permanent `slug`, a `solved_at` timestamp, and all replies.

`Rooms::Forum#post!(title:, body:)` creates both in one transaction, in the poster's `Current.user` context. Replies live in the post-thread and keep normal unread behavior; the opening message does not — the forum's `receive` is a no-op, so a new post never marks the forum unread or bumps chat counters. The gallery surfaces new posts by activity order instead of by an unread badge.

## Where it renders

| Surface | Route | Renders |
|---------|-------|---------|
| Gallery | `/rooms/:id` — `RoomsController#show` → `render_forum_gallery` | `rooms/forums/gallery`, inside the normal room shell in place of the message stream |
| Post (in-app) | opens in the thread panel from a gallery card | `rooms/threads/show` with the forum post header |
| Post (canonical) | `/f/:slug` — `ForumPostsController#show` (`forum_post_path`) | standalone page, no redirect — the permanent, shareable link |

The canonical `/f/:slug` page is member-gated in v1 but is deliberately a standalone render (not the in-app panel) so it can become public and SEO-indexable later — mirroring the utility of a classic web forum.

## Composing

**New post** lives in the top nav (`rooms/show/nav`) and reveals an inline composer at the top of the gallery — no route change. Because the nav renders in a separate DOM subtree, the button reaches the gallery's `forum_compose` controller through a `forum-compose-opener` Stimulus outlet. The composer has a title field and a rich body that reuses the chat composer: the Trix editor with `@`-mention autocomplete, a rich-text toolbar toggle, and inline file attachments (`forum_body` controller). It submits to `Rooms::Forums::PostsController#create`, which calls `post!`.

## Filtering & sorting

The filter bar (`rooms/forums/_filter_bar`) offers:

- **Solved** — All / Open / Solved (`?solved=`), filtered on `solved_at` presence.
- **Sort** — Recent (`last_active_at`, default) / Newest (`created_at`) (`?sort=`).

Both are plain query params read by `Rooms::Forum#posts(solved:, sort:)`.

## Solved state

A post is **solved** when its thread has a `solved_at` (`Rooms::Thread#solved?`). Toggling goes through `Rooms::Forums::Posts::SolutionsController`:

- `create` → `solve!` ("Mark solved")
- `destroy` → `reopen!` ("Reopen")

A title or Solved change triggers `Rooms::Thread`'s `after_update_commit :broadcast_content_change`, which live-refreshes the post header (title + Solved badge) and the gallery card everywhere they render.

## Slugs

Each post gets a permanent, URL-safe `slug` derived from its title on first save (`Rooms::Thread#assign_forum_post_slug`). The `rooms.slug` unique index is the hard guarantee against collisions; two same-titled posts that race are resolved by a retry in `post!` that picks the next numbered suffix.

## Post options menu

The `⋯` menu on a post header (`rooms/forums/_post_header`) is available to every viewer:

| Item | Who | Action |
|------|-----|--------|
| Copy link | Anyone | Copies the canonical `/f/:slug` URL (`copy-to-clipboard`) |
| Edit | Admin / post creator | Edit the title **inline** — `edit` swaps a form into the header's title turbo-frame (`dom_id(post, :title)`), like a message edits in place; `update` redirects so the frame swaps back |
| Mark solved / Reopen | Admin / post creator | Toggle the solved state |

## Live updates

The gallery subscribes to `turbo_stream_from @room, :posts` and `turbo_stream_from @membership`. **Existing** cards live-refresh via replace broadcasts — a reply updates the card's reply count, activity, and participant avatars (`Message::Threadable#update_forum_gallery_card`); a title or Solved change refreshes the card and the post header (`Rooms::Thread#broadcast_content_change`). The membership subscription is what lets the nav's involvement bell cycle its state.

Brand-new posts are **not** appended live — they show on the next gallery load (the author is redirected to the gallery on create).

## Identity

Forum rooms use the `message-log` glyph across the sidebar indicator, the create-room form, the empty state, and the gated page (`room_type_indicator`).

## Key files

| Area | Files |
|------|-------|
| Models | `app/models/rooms/forum.rb`, `app/models/rooms/thread.rb` |
| Controllers | `app/controllers/rooms/forums_controller.rb`, `rooms/forums/posts_controller.rb`, `rooms/forums/posts/solutions_controller.rb`, `forum_posts_controller.rb` |
| Views | `app/views/rooms/forums/*`, `app/views/forum_posts/*` |
| JS | `app/javascript/controllers/forum_compose_controller.js`, `forum_compose_opener_controller.js`, `forum_body_controller.js` |
| Styles | `app/assets/stylesheets/application/forum.css` |
| Routes | `config/routes.rb` — `resources :forums` (+ nested `posts` / `solution`), `/f/:slug` |

## Not in v1

Post tags/categories were considered and cut to keep the first version simple — there is no taxonomy on posts. Public (unauthenticated) access to `/f/:slug` and SEO indexing are the intended next step but are not enabled yet.
