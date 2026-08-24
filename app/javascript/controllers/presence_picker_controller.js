import { Controller } from "@hotwired/stimulus"

// Presence picker in the profile flyout (Sidebar v2.1 account menu): three
// options, one always selected, applied immediately. Like the star toggle,
// a click owns its state optimistically — the option row, the footer avatar
// dot and the presence line under the name update at once, then the choice
// syncs in the background. Nothing broadcasts; the server only stores it.
export default class extends Controller {
  static targets = [ "option", "line" ]
  static values = { url: String }

  #desired = null
  #persisted = null
  #syncing = false

  connect() {
    this.#persisted =
      this.optionTargets.find(option => option.getAttribute("aria-checked") === "true")?.dataset.status
    this.#desired = this.#persisted
    this.element.dataset.presence ||= this.#persisted
  }

  choose(event) {
    const status = event.currentTarget.dataset.status
    if (status === this.#desired) return

    this.#desired = status
    this.#render(status)
    this.#sync()
  }

  #render(status) {
    this.optionTargets.forEach(option => {
      option.setAttribute("aria-checked", String(option.dataset.status === status))
    })

    // The footer dot is colored from [data-presence] on this element (sidebar.css)
    this.element.dataset.presence = status

    if (this.hasLineTarget) {
      this.lineTarget.textContent =
        this.optionTargets.find(option => option.dataset.status === status)
          ?.querySelector(".sidebar__presence-option-label")?.textContent ?? status
    }
  }

  // One request at a time, always sending the latest desired state — so rapid
  // clicks can't reach Rails out of order and collapse to a stale presence.
  async #sync() {
    if (this.#syncing) return
    this.#syncing = true

    try {
      while (this.#desired !== this.#persisted) {
        const desired = this.#desired
        const response = await fetch(this.urlValue, {
          method: "PATCH",
          headers: {
            "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
            "Accept": "text/vnd.turbo-stream.html"
          },
          body: new URLSearchParams({ status: desired }),
          credentials: "same-origin"
        })
        if (!response.ok) throw new Error(`Presence update failed: ${response.status}`)
        this.#persisted = desired
      }
    } catch (error) {
      console.warn("[PresencePicker]", error)
      // The write didn't land — snap back to what the server still holds so
      // the picker can't sit opposite the stored preference.
      this.#desired = this.#persisted
      this.#render(this.#persisted)
    } finally {
      this.#syncing = false
    }
  }
}
