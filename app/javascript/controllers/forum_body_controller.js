import { Controller } from "@hotwired/stimulus"

// Rich-text affordances for the forum post body: reveals the formatting toolbar.
// Like the chat composer, the editor's own file attachments are disabled — forum
// posts are text/rich-text only.
export default class extends Controller {
  static targets = ["text"]
  static classes = ["toolbar"]

  toggleToolbar() {
    this.element.classList.toggle(this.toolbarClass)
    this.textTarget.focus()
  }
}
