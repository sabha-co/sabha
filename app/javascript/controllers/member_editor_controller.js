import { Controller } from "@hotwired/stimulus"
import { get, post, destroy } from "@rails/request.js"
import { debounce } from "helpers/timing_helpers"

// Roster editor for a private room's Members tab. Empty box: the roster shows,
// loaded a page at a time as it scrolls. Typing runs one server search over
// everyone the room could hold — matching members (to remove) and non-members
// (to add) — and swaps that in for the roster until the box is cleared.
export default class extends Controller {
  static values = { membersUrl: String }
  static targets = [ "input", "results", "roster", "error" ]

  initialize() {
    this.search = debounce(this.search.bind(this), 200)
  }

  async search() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim() : ""
    this.#clearError()

    if (query.length < 2) {
      this.#showRoster()
      return
    }

    const response = await get(this.membersUrlValue, { query: { query }, responseKind: "html" })
    if (response.ok) {
      this.resultsTarget.innerHTML = await response.text
      this.resultsTarget.hidden = false
      if (this.hasRosterTarget) this.rosterTarget.hidden = true
    }
  }

  async add(event) {
    const button = event.currentTarget
    button.disabled = true
    this.#clearError()

    try {
      const response = await post(this.membersUrlValue, {
        body: JSON.stringify({ user_id: button.dataset.userId }),
        contentType: "application/json",
        responseKind: "turbo-stream"
      })

      if (response.ok) {
        this.#reset()
      } else {
        button.disabled = false
        this.#showError("Couldn't add them. Try again.")
      }
    } catch {
      button.disabled = false
      this.#showError("Couldn't add them. Try again.")
    }
  }

  async remove(event) {
    const button = event.currentTarget
    const userId = button.dataset.userId
    button.disabled = true
    this.#clearError()

    try {
      const response = await destroy(`${this.membersUrlValue}/${userId}`, { responseKind: "turbo-stream" })
      if (response.ok) {
        this.#rowsFor(userId).forEach(row => row.remove())
      } else {
        button.disabled = false
        this.#showError("Someone has to stay in the room.")
      }
    } catch {
      button.disabled = false
      this.#showError("Couldn't remove them. Try again.")
    }
  }

  // A member can appear in both the roster and the open search results, so drop
  // every row for them, not just the one whose button was clicked.
  #rowsFor(userId) {
    return this.element.querySelectorAll(`[data-member-id="${userId}"]`)
  }

  #reset() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.#showRoster()
  }

  #showRoster() {
    this.#hideResults()
    if (this.hasRosterTarget) this.rosterTarget.hidden = false
  }

  #hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.hidden = true
    }
  }

  #showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  #clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
