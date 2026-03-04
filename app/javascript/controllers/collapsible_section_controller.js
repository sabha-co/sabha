import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon", "toggle"]
  static values = { key: String }

  connect() {
    if (this.#isCollapsed()) this.#collapse()
  }

  toggle() {
    if (this.#isCollapsed()) {
      localStorage.removeItem(this.#storageKey)
      this.#expand()
    } else {
      localStorage.setItem(this.#storageKey, "1")
      this.#collapse()
    }
  }

  #collapse() {
    this.contentTarget.hidden = true
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
    if (this.hasIconTarget) this.iconTarget.style.transform = "rotate(-90deg)"
  }

  #expand() {
    this.contentTarget.hidden = false
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.hasIconTarget) this.iconTarget.style.transform = ""
  }

  #isCollapsed() {
    return localStorage.getItem(this.#storageKey) === "1"
  }

  get #storageKey() {
    return `collapsible:${this.keyValue}`
  }
}
