import { Controller } from "@hotwired/stimulus"

// Highlights the hover-bar quick reactions the current user has already used, and
// turns a click on a highlighted one into a removal instead of a duplicate add.
// "Mine" is read from the boost chips' booster ids — the actions bar is inside
// the cached, viewer-blind message render, so this can only be decided
// client-side. Re-syncs whenever the boosts frame is replaced.
export default class extends Controller {
  connect() {
    this.sync()
    this.observer = new MutationObserver(() => {
      this.sync()
      this.#restoreFocus()
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // On a quick-reaction submit for an emoji already mine, remove it (reusing that
  // chip's own remove form) rather than POSTing a duplicate the server ignores.
  route(event) {
    const emoji = this.#emojiOf(event.target)
    if (!emoji || !this.#mine.has(emoji)) return

    event.preventDefault()
    this.#chipFor(emoji)?.querySelector("[data-boost-toggle-target='removeForm']")?.requestSubmit()
  }

  sync() {
    const mine = this.#mine
    this.element.querySelectorAll(".message__quick-reaction").forEach(form => {
      const emoji = this.#emojiOf(form)
      form.classList.toggle("message__quick-reaction--active", !!emoji && mine.has(emoji))
    })
  }

  // After a chip toggle replaces the frame, move focus to the emoji's successor
  // so keyboard users don't get dropped to the top of the page. Only fires when a
  // chip toggle set the marker (never on someone else's broadcast).
  #restoreFocus() {
    const emoji = this.element.getAttribute("data-reaction-refocus")
    if (!emoji) return
    this.element.removeAttribute("data-reaction-refocus")

    // The surviving chip, else the add pill, else — when that was the last
    // reaction and the row is gone — the message author link (the actions bar is
    // visibility:hidden until revealed and can't take focus), so focus stays in
    // the message rather than dropping to the top of the page.
    const successor = this.#chipFor(emoji)?.querySelector(".boost__toggle") ||
      this.element.querySelector(".boost__add") ||
      this.element.querySelector(".message__author")
    successor?.focus()
  }

  get #mine() {
    const set = new Set()
    this.element.querySelectorAll(".boost[data-boost-toggle-content-value]").forEach(chip => {
      const ids = JSON.parse(chip.dataset.boostToggleBoosterIdsValue || "[]")
      if (ids.includes(Current.user.id)) set.add(chip.dataset.boostToggleContentValue)
    })
    return set
  }

  #emojiOf(form) {
    return form.querySelector("button[data-emoji]")?.dataset.emoji
  }

  #chipFor(emoji) {
    return this.element.querySelector(`.boost[data-boost-toggle-content-value="${CSS.escape(emoji)}"]`)
  }
}
