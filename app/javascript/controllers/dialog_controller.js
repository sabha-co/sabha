import { Controller } from "@hotwired/stimulus"

// Scrim dialog: a native <dialog> opened as a modal. The browser handles the
// focus trap, Esc, and returning focus on close; this controller adds the
// scrim-click close and the Turbo wiring (open once the inner frame has
// loaded, close after a successful in-dialog submit).
//
// Attach it to the <dialog> itself, or — when a trigger button lives beside
// the dialog — to a wrapper, with the dialog marked as the modal target.
export default class extends Controller {
  static targets = [ "modal" ]

  open() {
    if (!this.#dialog.open) this.#dialog.showModal()
  }

  close() {
    this.#dialog.close()
  }

  // A click lands on the <dialog> element itself only when it's on the
  // backdrop — every click inside the card targets a descendant.
  closeOnScrim(event) {
    if (event.target === this.#dialog) this.close()
  }

  // Menu semantics: activating any item dismisses the menu
  closeOnMenuAction(event) {
    if (event.target.closest("a[href], button")) this.close()
  }

  closeOnSubmit(event) {
    if (event.detail.success) this.close()
  }

  get #dialog() {
    return this.hasModalTarget ? this.modalTarget : this.element
  }
}
