import { Controller } from "@hotwired/stimulus"

// Rich-text affordances for the forum post body: reveal the Trix formatting
// toolbar and attach files inline as native ActionText attachments (uploaded on
// the fly via direct upload). Kept separate from the chat `composer` controller,
// whose file flow turns uploads into standalone messages — here they belong to
// the post body.
export default class extends Controller {
  static targets = ["text"]
  static classes = ["toolbar"]

  toggleToolbar() {
    this.element.classList.toggle(this.toolbarClass)
    this.textTarget.focus()
  }

  filePicked(event) {
    const editor = this.textTarget.editor
    if (editor) {
      for (const file of event.target.files) editor.insertFile(file)
    }
    event.target.value = null
  }
}
