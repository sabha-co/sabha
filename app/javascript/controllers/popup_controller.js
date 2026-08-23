import PopupBaseController from "controllers/popup_base"

// The <details>-based popup: the open state is the native `open` property, so the
// base's defaults for isOpen / markClosed already fit. This controller adds only
// the toggle wired to the <details> `toggle` event, which orients and lazily loads
// the menu's turbo frame the first time it opens.
export default class extends PopupBaseController {
  toggle() {
    this.orient()

    // Load turbo frame only when popup opens
    if (this.element.open) {
      this.cancelClose()

      const frame = this.menuTarget.querySelector('turbo-frame[data-turbo-frame-src]')
      if (frame && !frame.hasAttribute('src')) {
        // Set src from data attribute to trigger loading
        frame.src = frame.dataset.turboFrameSrc
        // Remove the data attribute to prevent re-loading
        delete frame.dataset.turboFrameSrc
      }
    }
  }
}
