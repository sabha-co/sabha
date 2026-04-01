import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hint"]

  validate() {
    const looksLikeEmail = /\S@\S/.test(this.element.querySelector("input").value)
    this.hintTarget.hidden = !looksLikeEmail
  }
}
