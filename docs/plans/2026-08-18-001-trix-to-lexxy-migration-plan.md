# Trix → Lexxy migration (Sabha)

**Status: IMPLEMENTED on branch `trix-to-lexxy`.** All suites green — self-hosted
`bin/rails test` (1850 runs, 0 failures), SaaS `SAAS=true bin/rails test saas/test/`
(305 runs, 0 failures), targeted system tests (`composer_test`, `everyone_confirm_test`)
pass, and production eager-load (`zeitwerk:check`) is clean. Verified end-to-end in a
real browser: `@`-mention prompt → insert → send → renders inline; opengraph unfurl.

Ported from `basecamp/once-campfire#224` (still open/unmerged — owner chose to port from
PR-head rather than wait). Reference: `~/dev/once-campfire` on `pr-224-lexxy`. Lexxy is a
Rails gem (`lexxy ~> 0.9.24` → 0.9.29), built on Lexical; Sabha runs the Rails 8.2 `:lexxy`
Action Text editor adapter. Docs: https://lexxy.dev/docs/.

---

## ⚠️ Behavioral changes (user-visible)

- **Editor is now Lexxy, not Trix.** Real `<p>` paragraphs, **markdown** shortcuts
  (`~~strike~~`, `**bold**`, ``` ``` ``` code fences, `>` quotes, `#` heading, lists) with
  paste auto-formatting, and **real-time code syntax highlighting** in the composer. This
  is a net capability increase over Trix.
- **New formatting survives to stored messages:** strikethrough `<s>`, underline `<u>`,
  highlight `<mark>`, and **tables** now render. Previously Trix couldn't produce these;
  now they arrive via markdown/paste and are no longer stripped. (Decision: allow tables to
  render — light bordered style added.)
- **Forum posts lost in-body file attachments.** Forums now behave like chat: the editor's
  attach button is gone and the body is text/rich-text only. (Decision: match chat.) Files
  in forum posts are no longer supported — a deliberate feature reduction.
- **Mention menu is capped at the top 5** (was up to ~20 in Sabha's old custom autocomplete)
  and restyled mobile-friendly (viewport-bounded, tap-sized rows, opens upward). The DM
  recipient picker is unchanged (still its fuller client-filtered list).
- **@mention profile popup** looks and behaves the same but is re-implemented: the in-message
  mention is now an inline `<span>` (Lexxy renders mentions inside `<p>`, where the old
  `<div>`/`<details>` would break the paragraph) driven by a new `mention_popup_controller`.
- **Toolbar is minimal** (bold/italic/heading/quote/code/link/list) — underline, highlight,
  tables, dividers, undo/redo buttons are hidden, matching Trix's spare toolbar. Their markup
  still round-trips from markdown/paste.
- **Editor file attachments are off in chat** (`toolbar: { attachments: false }`) — unchanged
  behavior: files go out as separate messages via the composer's own attach button.

No change to the stored message format (`<action-text-attachment>` HTML), the mention
content-type (`application/vnd.sabha.mention`), or the notifications/mentionees pipeline.

---

## Key findings & gotchas (discovered during implementation)

- **NEVER set `attachments: false` in `Lexxy.configure`.** It disables *all* attachment
  support; the mention prompt only arms its trigger when `editorElement.supportsAttachments`
  is true (prompt.js `#promptContentTypePermitted`), so it silently kills `@`-autocomplete
  **and** opengraph embeds. Use only `toolbar: { attachments: false }`. (This was the live
  "autocomplete not working" bug.)
- **Boot-order bug (fixed):** referencing `ActionText::Attachment::OpengraphEmbed` in a
  class-body constant breaks eager-loaded boots (that class is defined in a deferred
  `after_initialize` rails_ext file). Caught by the SaaS suite; would also have broken
  single-tenant **production**. `RichTextHelper` now builds the selector lazily in a method.
- **Endpoint serves two callers.** `autocompletable/users` returns HTML `<lexxy-prompt-item>`s
  to the mention prompt (Lexxy fetches `*/*` → `format.html` declared FIRST) and JSON to the
  DM recipient picker. Prompt filters by `filter`, picker by `query`. Fixed the picker's
  `fetch(url,{as:"json"})` → explicit `Accept: application/json` (bug #1).
- **Lexxy already allows table tags** in its own Action Text sanitizer initializer; Sabha's
  additions (`s/u/mark/thead/tfoot`) compose on top via `lib/rails_ext/action_text_allowed_tags.rb`.
- Sabha's autocomplete stayed mostly intact: only 2 Trix-coupled files deleted
  (`rich_autocomplete_controller.js`, `mentions_autocomplete_handler.js`); the DM picker
  engine is untouched.

## Fixed the 5 PR-head bugs while porting

1. DM-autocomplete Accept-header break (above).
2. `RemoveSoloUnfurledLinkText` trix/lexxy discrimination — now keys on `<p>` presence, not
   "any div" (a lexxy body with a legacy `div[sgid]` mention no longer mis-branches).
3. Table content-loss — tables now allowed through instead of silently stripped.
4. `OpengraphEmbed` had no validations → `attachment if valid?` never returned nil → nil-href
   self-links. Added `validates :href, presence: true`.
5. `escapeHTML` unsafe in attribute positions → added `escapeAttribute` in `dom_helpers.js`,
   used for `href`/`src` in `unfurl_controller.js`.

## Testing

- Unit/helper: `content_filters_test` (ported off the deleted twitter-avatar filter; added
  lexxy-body + `s/u/mark`/code coverage), new `rich_text_helper_test`, `autocompletable`
  controller test (added HTML-prompt + `@everyone` cases).
- System (Cuprite): `composer_test` (enter-send, mention insert+persist, **mention edit
  round-trip, legacy-Trix-body edit, paste-to-unfurl, click-to-open-mention-popup**), ported
  `everyone_confirm_test` (now passes — was a pre-existing failure), new Cuprite
  `RichTextEditorHelper` overriding `fill_in_rich_text_area` so the shared `send_message`
  keeps working (with `paste_in_composer`/`assert_edit_editor_text` for the edit/unfurl flows).

## ⚠️ Bugs the ported system tests caught (all fixed)

Porting the composer system tests from upstream (mention-edit round-trip, legacy-Trix edit,
paste-to-unfurl) surfaced three genuine regressions the migration had shipped — none were
covered by any existing test, which is exactly why they slipped through:

1. **Editing any message with a mention 500'd.** The migration removed
   `User::Mentionable#to_editor_content_attachment_partial_path` (and `Everyone`'s) as "dead
   Trix code," but Rails 8.2's editor adapter calls it (`ActionText::Attachments::Conversion#
   editor_attachment_content`) when loading a stored mention back into the composer. Its default
   falls back to `to_partial_path` → `users/user` (nonexistent) → `Missing partial`. Restored
   both, pointing at a new **`users/_editor_mention`** simple chip (the interactive
   `users/mention` popup is display-only); DRY'd the prompt's `<template type="editor">` onto it.
2. **The mention was silently dropped on edit.** Even past the 500, Rails' editor conversion
   regenerates the attachment node from the attachable, resetting `content-type` to
   `application/octet-stream` (the `ActionText::Attachable` default). That isn't in the editor's
   `permitted-attachment-types`, so Lexxy discarded the mention. Fixed by declaring
   `attachable_content_type => "application/vnd.sabha.mention"` on `User::Mentionable`
   (shared `CONTENT_TYPE` constant) and `Everyone`.
3. **The @mention profile popup was completely broken and inaccessible.** The inline-safe
   rewrite switched the trigger to `data-mention-popup-*` / `role`+`tabindex` and the menu to a
   `[data-open]` span, but: (a) `SabhaActionTextSafelist` still only allowed `data-popup-*`, so
   the sanitizer stripped `data-mention-popup-target`, `role`, and `tabindex` from every rendered
   mention — the trigger wasn't focusable and the controller's `menuTarget` didn't exist (Stimulus
   threw on click); (b) `.message:has([open])` didn't match `[data-open]`, so the open menu stayed
   paint-contained/clipped inside the row; (c) `#orient()` measured the menu while still
   `display:none` (zero rect); (d) the trigger handled Enter but not Space and never exposed
   `aria-expanded`. Fixed the safelist, the `:has()` rule, the orient ordering, and added
   Space + `aria-expanded`/`aria-haspopup`. A new `composer_test` case clicks a mention and
   asserts the popup opens and `aria-expanded` toggles.

## Notes / non-migration items in the diff

- **`SystemTestHelper#sign_in` fix** (`click_on "Sign In"`/`"log_in"` → fill + `click_on
  "Sign in"`) is a PRE-EXISTING infra fix — the stale helper broke *every* system test on
  this branch (the fix otherwise lives on the unmerged redesign branch). Included here so the
  new/ported system tests can run; may conflict with that branch.
- Pre-existing benign console noise: `AbortError: signal is aborted without reason` — a lazy
  `message_profile` turbo-frame disconnected on optimistic-message re-render; the mention
  frame is unchanged from the old partial, so not introduced here.
- Incidental cleanup: removed dead Trix-era `to_editor_content_attachment_partial_path` from
  `User::Mentionable` and `Everyone`.
