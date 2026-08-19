import { Controller } from "@hotwired/stimulus"

// Opens the enclosing <dialog> the moment this element is inserted. Used for
// dialogs revealed by a turbo-stream (the bearer-key dialog) — a stream update
// never fires turbo:frame-load, so the frame-load→open wiring can't reach it.
export default class extends Controller {
  connect() {
    const dialog = this.element.closest("dialog")
    if (dialog && !dialog.open) dialog.showModal()
  }
}
