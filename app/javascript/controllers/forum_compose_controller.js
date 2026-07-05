import { Controller } from "@hotwired/stimulus"

// The "New post" composer is a native <details> disclosure: the <summary> opens
// and closes it, and CSS handles the styling and the ＋/✕ affordance. The one
// thing HTML can't do is move focus into the panel on open — that's this
// controller's only job.
export default class extends Controller {
  static targets = ["title"]

  focus() {
    if (this.element.open) this.titleTarget?.focus()
  }
}
