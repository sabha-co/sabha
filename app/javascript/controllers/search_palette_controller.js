import { Controller } from "@hotwired/stimulus"

// Sits on each search entry point (sidebar row, composer search button) and
// opens the layout-mounted palette in place of navigating — the href stays as
// the no-JS fallback. Also rewrites the shortcut hint off Apple platforms.
export default class extends Controller {
  static targets = [ "kbd" ]

  connect() {
    if (this.hasKbdTarget && !/Mac|iP/.test(navigator.platform)) {
      this.kbdTarget.textContent = "Ctrl+K"
    }
  }

  open(event) {
    const palette = document.getElementById("search_palette")
    if (!palette) return

    event.preventDefault()
    palette.showModal()
  }
}
