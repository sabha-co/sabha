import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["autoJoinOption"]
  static values = { openUrl: String, closedUrl: String }

  selectType(event) {
    const isOpen = event.target.value === "open"
    const url = isOpen ? this.openUrlValue : this.closedUrlValue
    this.element.setAttribute("action", url)

    if (this.hasAutoJoinOptionTarget) {
      this.autoJoinOptionTarget.hidden = !isOpen
    }
  }
}
