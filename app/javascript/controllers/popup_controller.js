import { Controller } from "@hotwired/stimulus"

const BOTTOM_THRESHOLD = 90

export default class extends Controller {
  static targets = [ "menu" ]
  static classes = [ "orientationTop" ]
  static values = { boundary: String }

  close() {
    if (!this.element.open || this.menuTarget.classList.contains("is-closing")) return

    // Play the close animation, then hide once it ends. The stylesheet owns the
    // duration; we just react to animationend so the two never drift apart and
    // a reduced-motion (near-zero) animation closes instantly.
    this.menuTarget.classList.add("is-closing")
    this.menuTarget.addEventListener("animationend", this.#finishClose)
  }

  toggle() {
    this.#orient()

    // Load turbo frame only when popup opens
    if (this.element.open) {
      this.#cancelClose()

      const frame = this.menuTarget.querySelector('turbo-frame[data-turbo-frame-src]')
      if (frame && !frame.hasAttribute('src')) {
        // Set src from data attribute to trigger loading
        frame.src = frame.dataset.turboFrameSrc
        // Remove the data attribute to prevent re-loading
        delete frame.dataset.turboFrameSrc
      }
    }
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  #finishClose = (event) => {
    if (event.target !== this.menuTarget || event.animationName !== "popup-out") return
    this.#cancelClose()
    this.element.open = false
  }

  // Reopening (or finishing) cancels an in-flight close so a stale listener
  // can't yank a freshly reopened menu shut.
  #cancelClose() {
    this.menuTarget.removeEventListener("animationend", this.#finishClose)
    this.menuTarget.classList.remove("is-closing")
  }

  #orient() {
    this.element.classList.toggle(this.orientationTopClass, this.#distanceToBottom < BOTTOM_THRESHOLD)
    this.menuTarget.style.setProperty("--max-width", this.#maxWidth + "px")
  }

  get #distanceToBottom() {
    return this.#boundaryBottom - this.#boundingClientRect.bottom
  }

  // A scrolling ancestor (named via data-popup-boundary-value) can clip the popup
  // before it reaches the window edge, so flip upward against whichever comes first.
  get #boundaryBottom() {
    return Math.min(this.#scrollBoundaryBottom, window.innerHeight)
  }

  get #scrollBoundaryBottom() {
    const boundary = this.boundaryValue && this.element.closest(this.boundaryValue)
    return boundary ? boundary.getBoundingClientRect().bottom : window.innerHeight
  }

  get #maxWidth() {
    return window.innerWidth - this.#boundingClientRect.left
  }

  get #boundingClientRect() {
    return this.menuTarget.getBoundingClientRect()
  }
}
