import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { words: Array, interval: { type: Number, default: 3000 } }

  connect() {
    this.index = 0
    this.timer = setInterval(() => this.#rotate(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.swapTimer)
  }

  #rotate() {
    this.element.classList.remove("is-visible")
    this.element.classList.add("is-out")

    this.swapTimer = setTimeout(() => {
      this.index = (this.index + 1) % this.wordsValue.length
      this.element.textContent = this.wordsValue[this.index]
      this.element.classList.remove("is-out")
      this.element.classList.add("is-in")

      this.element.offsetHeight
      this.element.classList.remove("is-in")
      this.element.classList.add("is-visible")
    }, 300)
  }
}
