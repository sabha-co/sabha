import { Controller } from "@hotwired/stimulus"

// Drives the New message screen: as recipients are added to or removed from the
// To: picker, it retitles the empty state, retargets the composer placeholder,
// and enables Send only once there is at least one recipient and a message.
export default class extends Controller {
  static targets = [ "title", "blurb", "input", "send" ]

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

    this.titleTarget.textContent = hasRecipients ? "No messages yet" : "Who is this for?"
    this.blurbTarget.textContent = hasRecipients
      ? "They'll see this conversation once you send the first message."
      : "Direct messages are private to the people in them. Add one or more people to start."

    this.inputTarget.placeholder = this.#placeholder(names)

    const ready = hasRecipients && this.inputTarget.value.trim().length > 0
    this.sendTarget.disabled = !ready
  }

  #placeholder(names) {
    if (names.length === 0) return "Add someone above first"
    if (names.length === 1) return `Message ${names[0].split(" ")[0]}`
    return `Message ${names.length} people`
  }
}
