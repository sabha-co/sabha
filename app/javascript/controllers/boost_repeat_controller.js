import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "form" ]

  perform(event) {
    const { target } = event
    const { boosterId } = event.params

    if (target.closest('[data-stop-propagation]')) return
    if (Current.user.id === boosterId) return
    if (this.element.classList.contains("busy")) return

    this.element.classList.add("busy")
    this.formTarget.addEventListener("turbo:submit-end", () => {
      this.element.classList.remove("busy")
    }, { once: true })
    this.formTarget.requestSubmit()
  }
}
