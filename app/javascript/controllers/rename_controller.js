import { Controller } from "@hotwired/stimulus"

// Keeps the rename dialog's Save button inert until the name is both non-empty
// and actually changed — a rename shouldn't save a blank name or a no-op. The
// server still applies whatever it receives; this is just guardrail UX.
export default class extends Controller {
  static targets = [ "field", "submit" ]

  connect() {
    this.original = this.fieldTarget.value.trim()
    this.update()
  }

  update() {
    const name = this.fieldTarget.value.trim()
    this.submitTarget.disabled = name.length === 0 || name === this.original
  }
}
