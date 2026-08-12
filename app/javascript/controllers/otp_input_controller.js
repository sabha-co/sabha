import { Controller } from "@hotwired/stimulus"
import { sanitize } from "models/otp_code"

// Six discrete cells that behave like one code field: typing advances, paste
// (or an OS one-time-code autofill) spreads across the cells, backspace walks
// back, and every keystroke is normalized the same way OtpCode.sanitize
// normalizes on the server. The concatenated value is mirrored into a hidden
// `code` input, so the form still submits a single `code` param unchanged.
export default class extends Controller {
  static targets = ["cell", "code"]

  connect() {
    this.sync()
  }

  input(event) {
    const cell = event.target
    const cleaned = sanitize(cell.value)

    if (cleaned.length > 1) {
      // A paste or an autofill can land several characters in one cell.
      this.fill(cleaned, this.cellTargets.indexOf(cell))
    } else {
      cell.value = cleaned
      if (cleaned) this.next(cell)?.focus()
    }

    this.sync()
  }

  keydown(event) {
    const cell = event.target

    if (event.key === "Backspace" && !cell.value) {
      const previous = this.previous(cell)
      if (previous) {
        previous.value = ""
        previous.focus()
        event.preventDefault()
        this.sync()
      }
    } else if (event.key === "ArrowLeft") {
      this.previous(cell)?.focus()
      event.preventDefault()
    } else if (event.key === "ArrowRight") {
      this.next(cell)?.focus()
      event.preventDefault()
    }
  }

  paste(event) {
    event.preventDefault()
    this.fill(sanitize(event.clipboardData.getData("text")), this.cellTargets.indexOf(event.target))
    this.sync()
  }

  // Spread `text` across the cells from `start`, then focus the last one filled.
  fill(text, start) {
    Array.from(text).forEach((char, offset) => {
      const cell = this.cellTargets[start + offset]
      if (cell) cell.value = char
    })

    const landed = Math.min(start + text.length, this.cellTargets.length) - 1
    this.cellTargets[Math.max(0, landed)]?.focus()
  }

  sync() {
    this.codeTarget.value = this.cellTargets.map((cell) => cell.value).join("")
  }

  next(cell) {
    return this.cellTargets[this.cellTargets.indexOf(cell) + 1]
  }

  previous(cell) {
    return this.cellTargets[this.cellTargets.indexOf(cell) - 1]
  }
}
