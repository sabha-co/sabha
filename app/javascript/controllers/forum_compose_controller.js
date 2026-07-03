import { Controller } from "@hotwired/stimulus"

// Toggles the "New post" compose form in place at the top of the forum gallery,
// Discord-style — no route change. The form lives in the page (hidden); opening
// it just reveals it and focuses the title.
export default class extends Controller {
  static targets = ["opener", "form", "title"]

  open(event) {
    event?.preventDefault()
    this.formTarget.hidden = false
    if (this.hasOpenerTarget) this.openerTarget.hidden = true
    this.titleTarget?.focus()
  }

  close(event) {
    event?.preventDefault()
    this.formTarget.hidden = true
    if (this.hasOpenerTarget) this.openerTarget.hidden = false
  }
}
