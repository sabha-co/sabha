import { Controller } from "@hotwired/stimulus"

// Favourite toggle for the room panel. The star endpoint only answers head :ok
// (it broadcasts the sidebar itself), so the panel button owns its own state:
// it flips optimistically and posts in the background. Method is derived from
// the new state each click, so repeated toggles stay correct.
export default class extends Controller {
  static values = { url: String, starred: Boolean }
  static targets = [ "label" ]

  toggle() {
    this.starredValue = !this.starredValue
    this.#render()
    this.#persist()
  }

  #render() {
    this.element.classList.toggle("roster__fav--on", this.starredValue)
    this.element.setAttribute("aria-pressed", String(this.starredValue))
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.starredValue ? "Favorited" : "Favorite"
    }
  }

  #persist() {
    fetch(this.urlValue, {
      method: this.starredValue ? "POST" : "DELETE",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      credentials: "same-origin"
    })
  }
}
