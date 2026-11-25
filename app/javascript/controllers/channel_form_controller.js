import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["autoJoinOption"]
  static values = { openUrl: String, closedUrl: String, forumUrl: String }

  selectType(event) {
    const type = event.target.value
    const url = type === "closed" ? this.closedUrlValue
      : type === "forum" ? this.forumUrlValue
      : this.openUrlValue
    this.element.setAttribute("action", url)

    if (this.hasAutoJoinOptionTarget) {
      this.autoJoinOptionTarget.hidden = type !== "open"
    }
  }
}
