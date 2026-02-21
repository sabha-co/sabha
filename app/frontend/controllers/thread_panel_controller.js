import { Controller } from "@hotwired/stimulus"

const TRANSITION_DURATION = 300

export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.frameTarget.addEventListener("turbo:frame-load", this.#onFrameLoad)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:frame-load", this.#onFrameLoad)
    clearTimeout(this.#closeTimer)
  }

  open() {
    clearTimeout(this.#closeTimer)
    this.element.removeAttribute("hidden")
    // Double rAF: first ensures display change is painted, second triggers transition
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (this.element.isConnected) {
          document.body.classList.add("thread-panel-open")
        }
      })
    })
  }

  close() {
    document.body.classList.remove("thread-panel-open")
    this.#closeTimer = setTimeout(() => {
      this.element.setAttribute("hidden", "")
      this.frameTarget.innerHTML = ""
    }, TRANSITION_DURATION)
  }

  #closeTimer

  closeOnEscape(event) {
    if (event.key === "Escape" && this.#isOpen) {
      this.close()
    }
  }

  // Skip transition on navigation — instant close so layout is clean before Turbo replaces the page
  closeOnNavigation() {
    if (this.#isOpen) {
      document.body.classList.remove("thread-panel-open")
      this.element.setAttribute("hidden", "")
      this.frameTarget.innerHTML = ""
    }
  }

  get #isOpen() {
    return document.body.classList.contains("thread-panel-open")
  }

  #onFrameLoad = () => {
    this.open()
  }
}
