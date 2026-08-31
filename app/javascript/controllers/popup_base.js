import { Controller } from "@hotwired/stimulus"

const BOTTOM_THRESHOLD = 90

// Shared positioning and close lifecycle for the two popup flavors — the
// <details>-based `popup` and the inline `mention-popup`. The only thing that
// genuinely differs between them is how "open" is represented, so a subclass
// overrides just three things: the `isOpen` getter, `markClosed()`, and its own
// open/toggle path (which calls `orient()` once the menu is visible). Every
// geometry read and every close path lives here so the copy-link and timestamp
// popups are structurally unable to disagree.
export default class PopupBaseController extends Controller {
  static targets = [ "menu" ]
  static classes = [ "orientationTop" ]
  static values = { boundary: String }

  close() {
    if (!this.isOpen || this.menuTarget.classList.contains("is-closing")) return

    // Play the close animation, then hide once it ends. The stylesheet owns the
    // duration; we just react to animationend so the two never drift apart and
    // a reduced-motion (near-zero) animation closes instantly.
    this.menuTarget.classList.add("is-closing")
    this.menuTarget.addEventListener("animationend", this.#finishClose)
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  // How the open state is represented — overridden by subclasses.
  get isOpen() {
    return this.element.open
  }

  // How the open state is torn down once the close animation ends — overridden
  // by subclasses (the sole tail difference between the two #finishClose paths).
  markClosed() {
    this.element.open = false
  }

  orient() {
    this.element.classList.toggle(this.orientationTopClass, this.#distanceToBottom < BOTTOM_THRESHOLD)
    this.menuTarget.style.setProperty("--max-width", this.#maxWidth + "px")
  }

  // Reopening (or finishing) cancels an in-flight close so a stale listener
  // can't yank a freshly reopened menu shut. Public because the subclasses call
  // it from their own open/toggle paths.
  cancelClose() {
    this.menuTarget.removeEventListener("animationend", this.#finishClose)
    this.menuTarget.classList.remove("is-closing")
  }

  #finishClose = (event) => {
    if (event.target !== this.menuTarget || event.animationName !== "popup-out") return
    this.cancelClose()
    this.markClosed()
  }

  get #distanceToBottom() {
    return this.#boundaryBottom - this.#boundingClientRect.bottom
  }

  // A scrolling ancestor (named via the controller's boundary value) can clip the
  // popup before it reaches the window edge, so flip upward against whichever
  // comes first.
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
