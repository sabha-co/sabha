import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  checkMatch() {
    const expected = this.inputTarget.dataset.expected
    this.buttonTarget.disabled = this.inputTarget.value !== expected
  }
}
