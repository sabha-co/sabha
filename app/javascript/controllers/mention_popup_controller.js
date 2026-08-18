import { Controller } from "@hotwired/stimulus"

const BOTTOM_THRESHOLD = 90

// Inline-safe cousin of the <details>-based `popup` controller, used by @mentions
// that render inside Lexxy's <p> paragraphs where <details>/<div> would split the
// paragraph. Same look and behavior; the open state is a data-open attribute on an
// inline <span> rather than the native <details open> property. The lazy turbo
// frame inside the menu loads on its own once the menu becomes visible.
export default class extends Controller {
  static targets = [ "menu", "summary" ]
  static classes = [ "orientationTop" ]
  static values = { boundary: String }

  toggle(event) {
    event.preventDefault()
    this.#isOpen ? this.close() : this.#open()
  }

  close() {
    if (!this.#isOpen || this.menuTarget.classList.contains("is-closing")) return

    // Play the close animation, then hide once it ends. The stylesheet owns the
    // duration; we just react to animationend so the two never drift apart and a
    // reduced-motion (near-zero) animation closes instantly.
    this.menuTarget.classList.add("is-closing")
    this.menuTarget.addEventListener("animationend", this.#finishClose)
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  #open() {
    this.#cancelClose()
    this.element.setAttribute("data-open", "")
    this.summaryTarget.setAttribute("aria-expanded", "true")
    // Orient after the menu is visible: a display:none menu measures as a zero
    // rect, which would never flip the popup upward and would mis-size its width.
    this.#orient()
  }

  get #isOpen() {
    return this.element.hasAttribute("data-open")
  }

  #finishClose = (event) => {
    if (event.target !== this.menuTarget || event.animationName !== "popup-out") return
    this.#cancelClose()
    this.element.removeAttribute("data-open")
    this.summaryTarget.setAttribute("aria-expanded", "false")
  }

  // Reopening (or finishing) cancels an in-flight close so a stale listener can't
  // yank a freshly reopened menu shut.
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

  // A scrolling ancestor (named via data-mention-popup-boundary-value) can clip the
  // popup before it reaches the window edge, so flip upward against whichever comes
  // first.
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
