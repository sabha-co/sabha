import { Controller } from "@hotwired/stimulus"

// Keeps a section's label count honest against the rows actually in its list.
// Row add/remove broadcasts (star, leave, room creation) mutate the list
// container directly; this observer re-counts on any such mutation, so the
// count never depends on which action produced the change. The count hides at
// zero, matching the server-rendered conditional.
export default class extends Controller {
  static targets = ["count"]
  static values = { container: String }

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
    const count = this.#list.querySelectorAll(".room-row").length
    this.countTargets.forEach((target) => {
      target.textContent = count
      target.hidden = count === 0
    })
    this.element.hidden = count === 0
  }

  get #list() {
    return document.getElementById(this.containerValue)
  }
}
