import { Controller } from "@hotwired/stimulus"

// Sidebar row density: comfortable (default) or compact. Stored per device in
// localStorage, mirroring the theme controller; the pre-paint script in
// layouts/_theme_preference stamps data-density so rows never flash on load.
export default class extends Controller {
  static targets = ["comfortableButton", "compactButton"]

  connect() {
    this.#apply()
    this.#updateButtons()
  }

  setComfortable() {
    this.#store("comfortable")
  }

  setCompact() {
    this.#store("compact")
  }

  #store(density) {
    localStorage.setItem("density", density)
    this.#apply()
    this.#updateButtons()
  }

  #apply() {
    if (this.#compact) {
      document.documentElement.setAttribute("data-density", "compact")
    } else {
      document.documentElement.removeAttribute("data-density")
    }
  }

  #updateButtons() {
    if (this.hasComfortableButtonTarget) {
      this.comfortableButtonTarget.setAttribute("aria-selected", !this.#compact)
    }
    if (this.hasCompactButtonTarget) {
      this.compactButtonTarget.setAttribute("aria-selected", this.#compact)
    }
  }

  get #compact() {
    return localStorage.getItem("density") === "compact"
  }
}
