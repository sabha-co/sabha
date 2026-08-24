import { Controller } from "@hotwired/stimulus"

// Drives the badge editor's live preview: the chip mirrors the typed name and
// the chosen hue, a counter tracks the 10-character cap, the hex prints beside
// the colour label, and the confirm button stays inert until the name is
// non-empty. The server enforces the same rules.
export default class extends Controller {
  static targets = [ "name", "icon", "counter", "preview", "hex", "picker", "submit" ]

  connect() {
    this.update()
  }

  update() {
    const name = this.nameTarget.value.trim()

    const icon = this.hasIconTarget ? this.iconTarget.value.trim() : ""
    this.previewTarget.textContent = [icon, name].filter(Boolean).join(" ") || "BADGE"
    this.counterTarget.textContent = `${this.nameTarget.value.length}/10`
    this.submitTarget.disabled = name.length === 0

    const color = this.#selectedColor
    if (color) {
      this.previewTarget.style.setProperty("--badge-color", color)
      if (this.hasHexTarget) this.hexTarget.textContent = color
    }
  }

  get #selectedColor() {
    return this.hasPickerTarget ? this.pickerTarget.value : undefined
  }
}
