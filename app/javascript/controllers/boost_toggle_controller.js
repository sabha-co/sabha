import { Controller } from "@hotwired/stimulus"

// A grouped reaction chip. Whether it's "mine" is decided here, client-side,
// because the chip's HTML is broadcast identically to every viewer and can't
// bake in a per-viewer boost id. Clicking submits the add form (join the
// reaction) or the remove form (drop mine), depending.
export default class extends Controller {
  static targets = [ "addForm", "removeForm" ]
  static values = { content: String, boosterIds: Array }

  connect() {
    this.element.classList.toggle("boost--mine", this.#mine)
    this.#toggleButton?.setAttribute("aria-pressed", this.#mine ? "true" : "false")
  }

  toggle(event) {
    if (this.element.classList.contains("busy")) return

    // The frame replacement below destroys this focused button. On keyboard
    // activation (a synthetic click carries detail 0) mark the emoji so the
    // reaction bar can move focus to its successor; mouse users don't need it and
    // shouldn't have the actions bar popped open under them.
    if (event?.detail === 0) {
      this.element.closest("[data-controller~='reaction-bar']")
        ?.setAttribute("data-reaction-refocus", this.contentValue)
    }

    const form = this.#mine ? this.removeFormTarget : this.addFormTarget
    this.element.classList.add("busy")
    form.addEventListener("turbo:submit-end", () => this.element.classList.remove("busy"), { once: true })
    form.requestSubmit()
  }

  get #mine() {
    return this.boosterIdsValue.includes(Current.user.id)
  }

  get #toggleButton() {
    return this.element.querySelector(".boost__toggle")
  }
}
