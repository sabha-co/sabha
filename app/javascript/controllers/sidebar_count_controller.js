import { Controller } from "@hotwired/stimulus"

// Keeps a section's label count honest against the rows actually in its list.
// Row add/remove broadcasts (star, leave, room creation) mutate the list
// container directly; this observer re-counts on any such mutation, so the
// count never depends on which action produced the change. The count hides at
// zero, matching the server-rendered conditional.
//
// hideWhenEmpty is opt-in and hides the whole section at zero rows —
// Favorites, Forums, and DMs use it so an empty section stays out of the way
// yet reappears the moment a row is broadcast in. Rooms keeps a persistent
// header, so it opts out. Room/forum rows are ".room-row" and DM rows are
// ".direct"; the count matches both.
export default class extends Controller {
  static targets = ["count"]
  static values = { container: String, hideWhenEmpty: Boolean }

  #observer = undefined;

  connect() {
    this.#observer = new MutationObserver(() => this.#sync())
    this.#observer.observe(this.#list, { childList: true })
    this.#sync()
  }

  disconnect() {
    this.#observer?.disconnect()
  }

  #sync() {
    const count = this.#list.querySelectorAll(".room-row, .direct").length
    this.countTargets.forEach((target) => {
      target.textContent = count
      target.hidden = count === 0
    })
    if (this.hideWhenEmptyValue) this.element.hidden = count === 0
  }

  get #list() {
    return document.getElementById(this.containerValue)
  }
}
