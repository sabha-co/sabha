import { Controller } from "@hotwired/stimulus"

// Keeps the confirm button inert until the bot has a non-empty name — the
// server enforces the same rule, this just makes the empty state obvious.
export default class extends Controller {
  static targets = [ "name", "submit" ]

  connect() {
    this.validate()
  }

  validate() {
    this.submitTarget.disabled = this.nameTarget.value.trim().length === 0
  }
}
