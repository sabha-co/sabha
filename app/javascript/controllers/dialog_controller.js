import { Controller } from "@hotwired/stimulus"

// Scrim dialog: a native <dialog> opened as a modal. The browser handles the
// focus trap, Esc, and returning focus on close; this controller adds the
// scrim-click close and the Turbo wiring (open once the inner frame has
// loaded, close after a successful in-dialog submit).
export default class extends Controller {
  open() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    this.element.close()
  }

  // A click lands on the <dialog> element itself only when it's on the
  // backdrop — every click inside the card targets a descendant.
  closeOnScrim(event) {
    if (event.target === this.element) this.close()
  }

  closeOnSubmit(event) {
    if (event.detail.success) this.close()
  }
}
