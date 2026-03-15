import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const STEPS = [
  { text: "Creating workspace\u2026", progress: 30 },
  { text: "Setting up rooms\u2026", progress: 60 },
  { text: "Almost ready!", progress: 90 },
]

const STEP_DURATION = 900
const FINAL_DELAY = 600

export default class extends Controller {
  static targets = ["bar", "status"]
  static values = { url: String }

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      Turbo.visit(this.urlValue)
      return
    }

    this.step = 0
    this.advance()
    this.timer = setInterval(() => this.advance(), STEP_DURATION)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
    if (this.redirect) clearTimeout(this.redirect)
  }

  advance() {
    if (this.step >= STEPS.length) {
      clearInterval(this.timer)
      this.barTarget.style.width = "100%"
      this.redirect = setTimeout(() => Turbo.visit(this.urlValue), FINAL_DELAY)
      return
    }

    const { text, progress } = STEPS[this.step]
    this.statusTarget.textContent = text
    this.barTarget.style.width = `${progress}%`
    this.step++
  }
}
