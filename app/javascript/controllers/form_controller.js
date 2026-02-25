import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = [ "cancel" ]

  initialize() {
    this.debouncedSubmit = debounce(this.debouncedSubmit.bind(this), 300)
  }

  submit() {
    this.element.requestSubmit()
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
