import PopupBaseController from "controllers/popup_base"

// Inline-safe cousin of the <details>-based `popup` controller, used by @mentions
// that render inside Lexxy's <p> paragraphs where <details>/<div> would split the
// paragraph. Same look and behavior; the open state is a data-open attribute on an
// inline <span> rather than the native <details open> property, so it overrides
// isOpen / markClosed and drives its own open path. The lazy turbo frame inside the
// menu loads on its own once the menu becomes visible.
export default class extends PopupBaseController {
  static targets = [ "summary" ]

  toggle(event) {
    event.preventDefault()
    this.isOpen ? this.close() : this.#open()
  }

  get isOpen() {
    return this.element.hasAttribute("data-open")
  }

  markClosed() {
    this.element.removeAttribute("data-open")
    this.summaryTarget.setAttribute("aria-expanded", "false")
  }

  #open() {
    this.cancelClose()
    this.element.setAttribute("data-open", "")
    this.summaryTarget.setAttribute("aria-expanded", "true")
    // Orient after the menu is visible: a display:none menu measures as a zero
    // rect, which would never flip the popup upward and would mis-size its width.
    this.orient()
  }
}
