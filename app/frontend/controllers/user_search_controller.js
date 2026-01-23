import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"
import { debounce } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = ["input", "results", "selected", "selectedHeader", "selectedSeparator"]
  static values = { url: String }

  initialize() {
    this.search = debounce(this.search.bind(this), 300)
    this.abortController = null
  }

  async search() {
    const query = this.inputTarget.value.trim()

    this.abortController?.abort()

    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    this.abortController = new AbortController()

    const selectedIds = this.#getSelectedUserIds()
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("query", query)
    selectedIds.forEach(id => url.searchParams.append("selected_ids[]", id))

    try {
      const response = await get(url, {
        responseKind: "html",
        signal: this.abortController.signal
      })

      if (response.ok) {
        this.resultsTarget.innerHTML = await response.html
      } else {
        this.resultsTarget.innerHTML = '<li class="txt-medium txt-deemphasize txt-align-center pad">Search failed</li>'
      }
    } catch (error) {
      if (error.name !== "AbortError") {
        this.resultsTarget.innerHTML = '<li class="txt-medium txt-deemphasize txt-align-center pad">Search failed</li>'
      }
    }
  }

  toggle(event) {
    const checkbox = event.target
    const userItem = checkbox.closest("li")

    if (checkbox.checked) {
      // Move to selected section
      this.#moveToSelected(userItem, checkbox)
    } else {
      // Remove from selected section
      userItem.remove()
      this.#updateSelectedHeader()
    }
  }

  #moveToSelected(userItem, checkbox) {
    // Clone the item for the selected section
    const clonedItem = userItem.cloneNode(true)

    // Update the cloned checkbox to use toggle action
    const clonedCheckbox = clonedItem.querySelector('input[type="checkbox"]')
    if (clonedCheckbox) {
      clonedCheckbox.checked = true
      clonedCheckbox.setAttribute("data-action", "change->user-search#toggle")
    }

    // Add to selected section
    this.selectedTarget.appendChild(clonedItem)

    // Remove from search results
    userItem.remove()

    this.#updateSelectedHeader()
  }

  #updateSelectedHeader() {
    const hasSelected = this.selectedTarget.children.length > 0
    if (this.hasSelectedHeaderTarget) {
      this.selectedHeaderTarget.style.display = hasSelected ? "" : "none"
    }
    if (this.hasSelectedSeparatorTarget) {
      this.selectedSeparatorTarget.style.display = hasSelected ? "" : "none"
    }
  }

  #getSelectedUserIds() {
    const checkboxes = this.selectedTarget.querySelectorAll('input[name="user_ids[]"]:checked')
    return Array.from(checkboxes).map(cb => cb.value)
  }
}
