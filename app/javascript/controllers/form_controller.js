import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = [ "cancel", "submit" ]

  initialize() {
    this.debouncedSubmit = debounce(this.debouncedSubmit.bind(this), 300)
  }

  connect() {
    if (this.hasSubmitTarget) {
      this.initialState = this.#serialize()
      this.refreshDirty()
    }
  }

  submit() {
    this.element.requestSubmit()
  }

  // Keep a gated submit inert until a field differs from what loaded.
  refreshDirty() {
    if (this.hasSubmitTarget) this.submitTarget.disabled = this.#serialize() === this.initialState
  }

  #serialize() {
    return new URLSearchParams(new FormData(this.element)).toString()
  }

  debouncedSubmit() {
    this.element.requestSubmit()
  }

  cancel() {
    this.cancelTarget?.click()
  }

  preventAttachment(event) {
    event.preventDefault()
  }
}
