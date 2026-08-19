import { Controller } from "@hotwired/stimulus"

// Drives the New message screen: as recipients are added to or removed from the
// To: picker, it retitles the empty state, retargets the composer placeholder,
// and enables Send only once there is at least one recipient and a message. All
// copy comes in as values from the view, so the strings live in one place.
export default class extends Controller {
  static targets = [ "title", "blurb", "input", "send" ]
  static values = {
    emptyTitle: String, pickedTitle: String,
    emptyBlurb: String, pickedBlurb: String,
    emptyHint: String, oneHint: String, manyHint: String
  }

  connect() {
    this.select = this.element.querySelector("select[name='user_ids[]']")
    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.select, { childList: true })
    this.refresh()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  refresh() {
    const names = Array.from(this.select.options).map(option => option.textContent.trim())
    const hasRecipients = names.length > 0

    this.titleTarget.textContent = hasRecipients ? this.pickedTitleValue : this.emptyTitleValue
    this.blurbTarget.textContent = hasRecipients ? this.pickedBlurbValue : this.emptyBlurbValue
    this.inputTarget.placeholder = this.#placeholder(names)

    const ready = hasRecipients && this.inputTarget.value.trim().length > 0
    this.sendTarget.disabled = !ready
  }

  #placeholder(names) {
    if (names.length === 0) return this.emptyHintValue
    if (names.length === 1) return this.oneHintValue.replace("%{name}", names[0].split(" ")[0])
    return this.manyHintValue.replace("%{count}", names.length)
  }
}
