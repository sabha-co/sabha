import { Controller } from "@hotwired/stimulus"

// Favourite toggle for the room panel. The star endpoint only answers head :ok
// (it broadcasts the sidebar itself), so the panel button owns its own state:
// it flips optimistically and posts in the background. Method is derived from
// the new state each click, so repeated toggles stay correct.
export default class extends Controller {
  static values = { url: String, starred: Boolean }
  static targets = [ "label" ]

  #persisted
  #syncing = false

  connect() {
    this.#persisted = this.starredValue
  }

  toggle() {
    this.starredValue = !this.starredValue
    this.#render()
    this.#sync()
  }

  #render() {
    this.element.classList.toggle("roster__fav--on", this.starredValue)
    this.element.setAttribute("aria-pressed", String(this.starredValue))
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.starredValue ? "Favorited" : "Favorite"
    }
  }

  // One request at a time, always sending the latest desired state — so rapid
  // toggles can't reach Rails out of order and collapse to the trailing state.
  async #sync() {
    if (this.#syncing) return
    this.#syncing = true

    try {
      while (this.starredValue !== this.#persisted) {
        const desired = this.starredValue
        const response = await fetch(this.urlValue, {
          method: desired ? "POST" : "DELETE",
          headers: {
            "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
            "Accept": "text/vnd.turbo-stream.html"
          },
          credentials: "same-origin"
        })
        if (!response.ok) throw new Error(`Star toggle failed: ${response.status}`)
        this.#persisted = desired
      }
    } catch (error) {
      console.warn("[StarToggle]", error)
      // The write didn't land — snap the button back to what the server still
      // holds so it can't sit opposite the real membership.
      this.starredValue = this.#persisted
      this.#render()
    } finally {
      this.#syncing = false
    }
  }
}
