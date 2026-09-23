import { Controller } from "@hotwired/stimulus"

// Opens and closes a <dialog> from a button beside it.
export default class extends Controller {
  static targets = [ "dialog" ]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
